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

Block{T}() where {T} = Block{T}(DateTime[], T[])

value_type(::Block{T}) where {T} = T

# TODO equality

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
function _slice(block::Block, time_start::DateTime, time_end::DateTime)
    i_first = searchsortedfirst(block.times, time_start)
    i_last = searchsortedfirst(block.times, time_end) - 1

    if (i_first > length(block) || i_last < 1)
        return Block{T}()
    elseif (i_first == 1 && i_last == length(block))
        # Avoid constructing views if we want the whole block.
        return block
    else
        return Block(
            @view(block.times[i_first:i_last]),
            @view(block.values[i_first:i_last]),
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
Base.first(block::Block) = (first(block.times), first(block.values))
Base.last(block::Block) = (last(block.times), last(block.values))

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
