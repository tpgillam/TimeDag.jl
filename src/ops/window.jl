# Windowed sum.
# Note that we are equating the `AlwaysTicks` parameter with the `emit_early` kwarg in the
#   `sum` function below.
# TODO this logic can be made generic for anny associative window op
struct WindowSum{T, AlwaysTicks} <: StatefulUnaryNodeOp{T, AlwaysTicks}
    window::Int64
end

struct WindowSumState{T} <: NodeEvaluationState
    window_state::FixedWindowAssociativeOp{T, +}
end

function create_evaluation_state(::Tuple{Node}, op::WindowSum{T}) where {T}
    return WindowSumState(FixedWindowAssociativeOp{T, +}(op.window))
end

# emit_early = true
function operator(::WindowSum{T, true}, state::WindowSumState{T}, x::T) where {T}
    update_state!(state.window_state, x)
    return window_value(state.window_state)
end

# emit_early = false
function operator(::WindowSum{T, false}, state::WindowSumState{T}, x::T) where {T}
    update_state!(state.window_state, x)
    should_tick = window_full(state.window_state)
    return (window_value(state.window_state), should_tick)
end

function sum(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowSum{value_type(x), emit_early}(window))
end
