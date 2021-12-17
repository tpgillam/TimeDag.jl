"""A node which fundamentally represents a constant available over all time."""
struct Constant{T} <: NodeOp{T}
    value::T
end

Base.hash(x::Constant, h::UInt64) = hash(x.value, hash(:Constant, h))
function Base.:(==)(x::Constant{T}, y::Constant{T}) where {T}
    # Add short-circuit, in case Base.:(==)(::T, ::T) doesn't have one.
    x.value === y.value && return true
    return x.value == y.value
end

function Base.show(io::IO, op::Constant)
    return print(io, "$(typeof(op).name.name){$(value_type(op))}($(op.value))")
end

mutable struct ConstantState <: NodeEvaluationState
    ticked::Bool
    ConstantState() = new(false)
end

create_evaluation_state(::Tuple{}, ::Constant) = ConstantState()

_is_constant(::NodeOp) = false
_is_constant(::Constant) = true
_is_constant(node::Node) = _is_constant(node.op)

value(op::Constant) = op.value
value(node::Node) = value(node.op)

"""Identity if the argument is a node, otherwise wrap it in a constant node."""
_ensure_node(node::Node) = node
_ensure_node(value::Any) = obtain_node((), Constant(value))

function run_node!(
    op::Constant{T},
    state::ConstantState,
    time_start::DateTime,
    ::DateTime,  # time_end
) where {T}
    # The convention is that we emit a single knot at the start of the evaluation interval.
    return if state.ticked
        Block{T}()
    else
        state.ticked = true
        Block(unchecked, [time_start], [op.value])
    end
end

"""
    constant(value) -> Node

Explicitly wrap `value` into a `TimeDag` constant node, regardless of its type.

In many cases this isn't required, since many `TimeDag` functions which expect nodes will
automatically wrap non-node arguments into a constant node.

!!! warning
    If `value` is already a node, this will wrap it up in an additional node. This is very
    likely not what you want to do.
"""
constant(value::T) where {T} = obtain_node((), Constant(value))
