"""A node which just wraps a block."""
struct BlockNode{T} <: NodeOp{T}
    block::Block{T}
end

create_evaluation_state(::Tuple{}, ::BlockNode) = _EMPTY_NODE_STATE

function run_node!(
    ::EmptyNodeEvaluationState,
    op::BlockNode{T},
    time_start::DateTime,
    time_end::DateTime
) where {T}
    return _slice(op.block, time_start, time_end)
end

# TODO Need to think about equality for BlockNode. It is used in equality testing for node,
# so we do *not* really want to do full equality checking on block's values since this could
# really slow down identity mapping.

block_node(block::Block) = obtain_node((), BlockNode(block))

# TODO Identity mapping... probably just want a cache of empty blocks by T somewhere?
empty_node(T) = block_node(Block{T}())
