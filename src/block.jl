# TODO parameterise time type?
# TODO probably a bunch of @inbounds can go everywhere.

# TODO Using an abstractvector for values requires some thought. The problem is whether or
#   not it would permit us to have views of an array.
#   Possibly we need a more general type here which can package other representations?
#   See Stheno ColVecs / RowVecs - they have the same problem.

struct Block{T}
    times::AbstractVector{DateTime}
    values::AbstractVector{T}

    function Block(
        times::AbstractVector{DateTime},
        values::AbstractVector{T}
    ) where {T}
        # TODO Need some way of skipping checks if we're confident they're unnecessary...?
        if length(times) != length(values)
            throw(ArgumentError(
                "Times have length $(length(times)), values $(length(values))"
            ))
        end
        # FIXME Should we enforce basic requirements on construction, e.g.
        #   -> time ordering
        #   -> no repeated timestamps
        #   -> same length of times & values
        #   -> How make times & values immutable? Subclass of AbstractVector that doesn't
        #       implement setindex! ?
        return new{T}(times, values)
    end
end

Block{T}() where {T} = Block(DateTime[], T[])

function Block(knots::Union{AbstractVector{Tuple{DateTime, T}},AbstractVector{Pair{DateTime, T}}}) where {T}
    n = length(knots)
    times = Vector{DateTime}(undef, n)
    values = _allocate_values(T, n)
    for (i, (time, value)) in enumerate(knots)
        @inbounds times[i] = time
        @inbounds values[i] = value
    end
    return Block(times, values)
end

value_type(::Block{T}) where {T} = T

# Blocks are considered immutable from the point of view of `duplicate`.
duplicate_internal(x::Block, ::IdDict) = x

# Equality & hash need to be defined, since we have defined an internal constructor.
Base.hash(a::Block, h::UInt) = hash(a.values, hash(a.times, hash(:Block, h)))
Base.:(==)(a::Block, b::Block) = a.times == b.times && a.values == b.values

# Make a block behave like a table with two columns, primarily for printing purposes.
Tables.istable(::Block) = true
Tables.columnaccess(::Block) = true
Tables.columns(block::Block) = block

const _BLOCK_COLUMNNAMES = (:times, :values)
Tables.schema(::Block{T}) where {T} = Tables.Schema(_BLOCK_COLUMNNAMES, (DateTime, T))
Tables.getcolumn(block::Block, i::Int) = Tables.getcolumn(block, _BLOCK_COLUMNNAMES[i])
function Tables.getcolumn(block::Block, nm::Symbol)
    if nm == :times
        return block.times
    elseif nm == :values
        return block.values
    else
        throw(ArgumentError("Unknown column $nm"))
    end
end
Tables.columnnames(::Block) = _BLOCK_COLUMNNAMES

function Base.show(io::IO, block::Block)
    return pretty_table(
        io, block;
        title="Block{$(value_type(block))}($(length(block)) knots)",
        tf=tf_markdown
    )
end

"""Slice the block so we contain values in the interval [time_start, time_end)."""
function _slice(block::Block{T}, time_start::DateTime, time_end::DateTime) where {T}
    i_first = searchsortedfirst(block.times, time_start)
    i_last = searchsortedfirst(block.times, time_end) - 1

    if (i_first > length(block) || i_last < 1)
        return Block{T}()
    elseif (i_first == 1 && i_last == length(block))
        # Avoid constructing views if we want the whole block.
        return block
    else
        return Block(
            @inbounds(@view(block.times[i_first:i_last])),
            @inbounds(@view(block.values[i_first:i_last])),
        )
    end
end

function Base.vcat(blocks::Block{T}...) where {T}
    return if length(blocks) == 1
        # Fast path for a single block.
        only(blocks)
    else
        # TODO Rather than using vcat here, we could use a function that more intelligently
        # merges views and ranges etc.
        Block(
            vcat((block.times for block in blocks)...),
            vcat((block.values for block in blocks)...),
        )
    end
end

# Indexing, iteration, etc.
Base.length(block::Block) = length(block.times)
Base.isempty(block::Block) = length(block) == 0
Base.firstindex(block::Block) = 1
Base.lastindex(block::Block) = length(block)
Base.getindex(block::Block, i::Int) = (block.times[i], block.values[i])

Base.eltype(::Block{T}) where {T} = Tuple{DateTime, T}
function Base.iterate(block::Block, state::Int=1)
    return if (state > length(block))
        nothing
    else
        (block[state], state + 1)
    end
end

"""
    _allocate_values(T, n::Int) -> AbstractVector{T}

Allocate some uninitialized memory that looks like a vector{T} of length `n`.
"""
function _allocate_values(T, n::Int)
    # TODO This is not necessarily optimal. See comment near definition of
    #   Block regarding what to do if we're viewing a dense array.
    #   The correct solution will probably involve dispatching based on the type of
    #   input.values.
    return Vector{T}(undef, n)
end

"""
    _equal_times(a::Block, b::Block) -> Bool

true => the times in blocks `a` and `b` are the same.
false => the times in blocks `a` and `b` may be different, or the same.

This function will try to return true for as many cases as possible, with the guarantee
that it will always run in constant time; i.e. it will never explicitly compare time values.
"""
function _equal_times(a::Block, b::Block)::Bool
    # FIXME This doesn't account for the case where e.g. a.times is a vector, and b.times is
    #   a view of the entirety of a.times.
    return a.times === b.times
end
