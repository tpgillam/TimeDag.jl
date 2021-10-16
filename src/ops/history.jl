"""A node which emits the last `window` knots as an array."""
struct History{T} <: UnaryNodeOp{Vector{T}}
    window::Int64
end

always_ticks(::History) = false  # only tick with a full window
stateless_operator(::History) = false
time_agnostic(::History) = true

struct HistoryState{T} <: NodeEvaluationState
    value_buffer::CircularBuffer{T}
end

function create_operator_evaluation_state(::Tuple{Node}, op::History{T}) where {T}
    return HistoryState(CircularBuffer{T}(op.window))
end

function operator!(
    ::History{T}, state::HistoryState{T}, value::T
)::Maybe{Vector{T}} where {T}
    buf = state.value_buffer
    push!(buf, value)
    isfull(buf) || return Maybe{Vector{T}}()
    return Maybe(copy(buf))
end

"""
    history(x::Node{T}, window::Int) -> Node{Vector{T}}

Create a node whose values represent the last `window` values seen in `x`.

Each value will be vector of length `window`, and the result will only start ticking once
`window` values have been seen. The vector value contains time-ordered observations, with
the most recent observation last.
"""
function history(x::Node, window::Int)
    window > 0 || throw(ArgumentError("history requires a positive window, got $window"))
    return obtain_node((x,), History{value_type(x)}(window))
end
