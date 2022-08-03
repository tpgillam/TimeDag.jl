"""A node which will never tick, but has a definite value type."""
struct Empty{T} <: NodeOp{T} end

Base.hash(::Empty{T}, h::UInt64) where {T} = hash(T, hash(:Empty, h))
# Add short-circuit, in case Base.:(==)(::T, ::T) doesn't have one.
Base.:(==)(::Empty{T}, ::Empty{T}) where {T} = true

Base.show(io::IO, op::Empty) = print(io, "$(typeof(op).name.name){$(value_type(op))}()")

stateless(::Empty) = true

_is_empty(::NodeOp) = false
_is_empty(::Empty) = true
_is_empty(node::Node) = _is_empty(node.op)

function run_node!(
    ::Empty{T}, state::EmptyNodeEvaluationState, ::DateTime, ::DateTime
) where {T}
    # We never tick, so always return an empty block.
    return Block{T}()
end

"""
    empty_node(T)

Construct a node with value type `T` which, if evaluated, will never tick.
"""
empty_node(T) = obtain_node((), Empty{T}())
