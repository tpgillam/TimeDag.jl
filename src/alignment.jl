"""Represent a technique for aligning two timeseries."""
abstract type Alignment end

"""For a pair (A, B), tick whenever A ticks so long as both nodes are active."""
struct LeftAlignment <: Alignment end

"""For a pair (A, B), tick whenever A or B ticks so long as both nodes are active."""
struct UnionAlignment <: Alignment end

"""For a pair (A, B), tick whenever A and B tick simultaneously."""
struct IntersectAlignment <: Alignment end

"""The default alignment for operators when not specified."""
const DEFAULT_ALIGNMENT = UnionAlignment()


# TODO There should be optimisations for constant nodes somewhere.
#   How should constant nodes work? Presumably some subtype of a NodeOp?


abstract type BinaryAlignedNodeOp{T, A <: Alignment} <: NodeOp{T} end

# TODO We might not need this if we dispatch on the alignment type.
# """Get the alignment type for this op."""
# alignment(::BinaryAlignedNodeOp{T, A}) = A

"""
    binary_operator(::BinaryAlignedNodeOp) -> callable

Get the binary operator that should be used for this node.
"""
function binary_operator end

# FIXME Add initial_values, and support for this.

# TODO This should be refactored, as it will be shared for all binary nodes.

mutable struct AlignmentState{L, R} <: NodeEvaluationState
    latest_l::Union{L, Nothing}
    latest_r::Union{R, Nothing}
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    ::BinaryAlignedNodeOp{T, A},
) where {T, A <: Alignment}
    return AlignmentState{value_type(parents[1]), value_type(parents[2])}(nothing, nothing)
end

function _equal_times(a::Block, b::Block)::Bool
    # FIXME This doesn't account for the case where e.g. a.times is a vector, and b.times is
    #   a view of the entirety of a.times.
    return a.times === b.times
end

"""Apply, assuming `input_l` and `input_r` have identical alignment."""
function _apply_fast_align_binary!(
    ::Type{T},
    state::AlignmentState,
    f,
    input_l::Block,
    input_r::Block,
) where {T}
    n = length(input_l)
    values = _allocate_values(T, n)
    for i in 1:n
        @inbounds values[i] = f(input_l.values[i], input_r.values[i])
    end

    # Update the alignment state.
    state.latest_l = last(input_l.values)
    state.latest_r = last(input_r.values)
    return Block(input_l.times, values)
end

function run_node!(
    state::AlignmentState{L, R},
    ::BinaryAlignedNodeOp{T, A},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T, L, R, A}
    if isempty(input_l) && isempty(input_r)
        # Nothing to do, since neither input has ticked.
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable
        return _apply_fast_align_binary!(T, state, +, input_l, input_r)
    else
        # FIXME
        error("Not implemented")
    end
end
