"""A node which fundamentally represents a constant available over all time."""
struct Constant{T} <: NodeOp{T}
    value::T
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

"""Identity if the argument is a node, otherwise wrap it in a constant node."""
_ensure_node(node::Node) = node
_ensure_node(value::Any) = obtain_node((), Constant(value))

function run_node!(
    state::ConstantState,
    op::Constant{T},
    time_start::DateTime,
    ::DateTime,  # time_end
) where {T}
    # The convention is that we emit a single knot at the start of the evaluation interval.
    return if state.ticked
        Block{T}()
    else
        state.ticked = true
        Block([time_start], [op.value])
    end
end

constant(value::T) where {T} = obtain_node((), Constant(value))
