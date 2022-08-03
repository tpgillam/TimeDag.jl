"""A node which just wraps a block."""
struct BlockNode{T} <: NodeOp{T}
    block::Block{T}
end

function Base.show(io::IO, ::BlockNode{T}) where {T}
    return print(io, "BlockNode{$T}")
end

Base.hash(x::BlockNode, h::UInt64) = hash(x.block, hash(:BlockNode, h))
Base.:(==)(x::BlockNode{T}, y::BlockNode{T}) where {T} = x.block == y.block
Base.isequal(x::BlockNode{T}, y::BlockNode{T}) where {T} = isequal(x.block, y.block)

stateless(::BlockNode) = true

function run_node!(
    op::BlockNode{T}, ::EmptyNodeEvaluationState, time_start::DateTime, time_end::DateTime
) where {T}
    return _slice(op.block, time_start, time_end)
end

"""
    block_node(block::Block)

Construct a node whose values are read directly from the given `block`.
"""
block_node(block::Block) = obtain_node((), BlockNode(block))

"""
A node op which ticks once a day at the specified local time of day.
"""
struct Iterdates <: NodeOp{DateTime}
    time_of_day::Time
    tz::TimeZone
end

stateless(::Iterdates) = true

"""
    _to_utc(dt::DateTime, tz::TimeZone) -> DateTime

Interpret naive `dt` to be in timezone `tz`. Return a naive `DateTime`, but in UTC.
"""
function _to_utc(dt::DateTime, tz::TimeZone)
    # If we are already in UTC, there's nothing to do.
    tz == tz"UTC" && return dt
    return ZonedDateTime(dt, tz).utc_datetime
end

function run_node!(
    op::Iterdates, ::EmptyNodeEvaluationState, time_start::DateTime, time_end::DateTime
)
    times = DateTime[]

    # Add some padding for safety — we will only emit those times that are in the correct
    # time range.
    d1 = Date(time_start) - Day(2)
    d2 = Date(time_end) + Day(2)
    for d in d1:Day(1):d2
        # Get the appropriate time of day in this timezone.
        t = _to_utc(d + op.time_of_day, op.tz)
        t < time_start && continue
        t >= time_end && break
        push!(times, t)
    end

    return Block(unchecked, times, times)
end

# TODO add the equivalent of an RDate step & offset, for valid steps. Not sure what the
#   equivalent of these in Julia would be...
"""
    iterdates(time_of_day::Time=Time(0), tz::TimeZone=tz"UTC", occurrence=1)

Create a node which ticks exactly once a day at `time_of_day` in timezone `tz`.

This defaults to midnight in UTC. If `tz` is set otherwise, then each knot will appear at
`time_of_day` in that timezone.

Note that:
    * All knot times in `TimeDag` are considered to be in UTC.
    * It is possible to select a `time_of_day` that does not exist for every day. This will
        lead to an exception being raised during evaluation.

In a given knot, each value will be of type `DateTime`, and equal the time of the knot.
"""
function iterdates(time_of_day::Time=Time(0), tz::TimeZone=tz"UTC")
    return obtain_node((), Iterdates(time_of_day, tz))
end

"""
A node op which ticks every `delta`, such that a knot would appear on `epoch`.
"""
struct Pulse <: NodeOp{DateTime}
    delta::Millisecond
    epoch::DateTime
end

stateless(::Pulse) = true

function run_node!(
    op::Pulse, ::EmptyNodeEvaluationState, time_start::DateTime, time_end::DateTime
)
    rem_ = (time_start - op.epoch) % op.delta
    pulse_start = rem_ == Millisecond(0) ? time_start : time_start + (op.delta - rem_)

    rem_ = (time_end - op.epoch) % op.delta
    pulse_end = rem_ == Millisecond(0) ? time_end - op.delta : time_end - rem_

    times = collect(pulse_start:(op.delta):pulse_end)
    return Block(unchecked, times, times)
end

# The Julia epoch. This is the DateTime whose internal representation is "0".
const _JULIA_EPOCH = DateTime(0, 1, 1) - Millisecond(Dates.DATETIMEEPOCH)

"""
    pulse(delta::TimePeriod[; epoch::DateTime])

Obtain a node which ticks every `delta`. Each value will equal the time of the knot.

Knots will be placed such that the difference between its time and `epoch` will always be an
integer multiple of `delta`. By default `epoch` is set to the Julia `DateTime` epoch, which
is `DateTime(0, 12, 31)`.
"""
function pulse(delta::TimePeriod; epoch::DateTime=_JULIA_EPOCH)
    delta > Millisecond(0) || throw(ArgumentError("delta must be positive, got $delta"))
    return obtain_node((), Pulse(Millisecond(delta), epoch))
end

# TODO We may want to generalise or otherwise refactor to allow reading multiple value
# fields.
# TODO we need some nicer APIs here, which will necessitate a new TeaFiles version.
"""A node which will read from an appropriately formatted TeaFile."""
struct TeaFileNode{T} <: NodeOp{T}
    path::String
    i_time_field::Int64
    i_value_field::Int64

    function TeaFileNode(path::AbstractString, value_field_name::AbstractString)
        # Verify that the file has a valid time index.
        metadata = open(path) do f
            read(f, TeaFiles.Header.TeaFileMetadata)
        end
        time_section = TeaFiles.Header.get_section(metadata, TeaFiles.Header.TimeSection)
        time_field = TeaFiles.Header.get_primary_time_field(metadata)
        compatible_time = (
            TeaFiles.Header.field_type(time_field) == Int64 &&
            TeaFiles.Header.is_julia_time_compatible(time_section)
        )
        if !compatible_time
            throw(ArgumentError("Got incompatible time field."))
        end

        item_section = TeaFiles.Header.get_section(metadata, TeaFiles.Header.ItemSection)
        i_value_field = only(findall(x -> x.name == value_field_name, item_section.fields))
        T = TeaFiles.Header.field_type(item_section.fields[i_value_field])

        # This is guaranteed to be unique.
        i_time_field = findfirst(x -> x.offset == time_field.offset, item_section.fields)

        return new{T}(path, i_time_field, i_value_field)
    end
end

function Base.hash(x::TeaFileNode, h::UInt64)
    return hash(x.path, hash(x.i_time_field, hash(x.i_value_field, hash(:TeaFileNode, h))))
end
function Base.:(==)(x::TeaFileNode{T}, y::TeaFileNode{T}) where {T}
    return (
        x.path == y.path &&
        x.i_time_field == y.i_time_field &&
        x.i_value_field == y.i_value_field
    )
end

# TODO One could imagine a more optimal reading process where the state contains the
#   location in the file we're up to, to avoid a binary search.
#   The current reading process in `run_node!` does wasteful allocation, which could also
#   be improved by dealing with a lower level API in TeaFiles (when exposed).
stateless(::TeaFileNode) = true

function run_node!(
    op::TeaFileNode{T}, ::EmptyNodeEvaluationState, time_start::DateTime, time_end::DateTime
) where {T}
    rows = TeaFiles.read(op.path; lower=time_start, upper=time_end)
    times = Vector{DateTime}(undef, length(rows))
    values = Vector{T}(undef, length(rows))

    @inbounds for (i, row) in enumerate(rows)
        times[i] = getfield(row, op.i_time_field)
        values[i] = getfield(row, op.i_value_field)
    end

    # Note that this is *not* unchecked, since we should not trust data that we retrieve
    # from disk - e.g. it may have been corrupted.
    return Block(times, values)
end

"""
    tea_file(path::AbstractString, value_field_name)

Get a node that will read data from the tea file at `path`.

Such a tea file must observe the following properties, which will be verified at runtime:
* Have a primary time field which is compatible with a Julia `DateTime`.
* Have exactly one column with name `value_field_name`.
* Have *strictly* increasing times.

Upon node creation, the metadata section of the file will be parsed to infer the value type
of the resulting node. However, the bulk of the data will only be read at evaluation time.

# See also
* The [tea file spec](http://discretelogics.com/resources/teafilespec/)
* [TeaFiles.jl](https://github.com/tpgillam/TeaFiles.jl)
"""
function tea_file(path::AbstractString, value_field_name::AbstractString)
    return obtain_node((), TeaFileNode(path, value_field_name))
end
tea_file(path::AbstractString, field_name::Symbol) = tea_file(path, string(field_name))
