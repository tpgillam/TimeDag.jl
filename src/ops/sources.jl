"""A node which just wraps a block."""
struct BlockNode{T} <: NodeOp{T}
    block::Block{T}
end

function Base.show(io::IO, ::BlockNode{T}) where {T}
    return print(io, "BlockNode{$T}")
end

Base.hash(x::BlockNode, h::UInt64) = hash(x.block, hash(:BlockNode, h))
Base.:(==)(x::BlockNode{T}, y::BlockNode{T}) where {T} = x.block == y.block

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

# TODO Identity mapping... probably just want a cache of empty blocks by T somewhere?
"""
    empty_node(T)

Construct a node with value type `T` which, if evaluated, will never tick.
"""
empty_node(T) = block_node(Block{T}())

"""
A node op which ticks once a day at the specified time.
"""
struct Iterdates <: NodeOp{DateTime}
    time_of_day::Time
end

stateless(::Iterdates) = true

function run_node!(
    op::Iterdates, ::EmptyNodeEvaluationState, time_start::DateTime, time_end::DateTime
)
    # Figure out the first time at the appropriate time of day.
    t1 = Date(time_start) + op.time_of_day
    t1 = t1 < time_start ? t1 + Day(1) : t1

    # Figure out the last time to emit.
    t2 = Date(time_end) + op.time_of_day
    t2 = t2 >= time_end ? t2 - Day(1) : t2

    times = t1:Day(1):t2
    return Block(unchecked, times, times)
end

# TODO add the equivalent of an RDate step & offset, for valid steps. Not sure what the
#   equivalent of these in Julia would be...
# TODO deal with timezones. Semantics here would be that the `time_of_day` would apply in
#   a particular timezone.
"""
    iterdates(time_of_day::Time=Time(0))

Create a node which ticks exactly once a day at `time_of_day`, which defaults to midnight.
In a given knot, each value will be of type `DateTime`, and equal the time of the knot.
"""
iterdates(time_of_day::Time=Time(0)) = obtain_node((), Iterdates(time_of_day))

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
