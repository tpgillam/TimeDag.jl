# Windowed associative binary operator.
# Note that we are equating the `AlwaysTicks` parameter with the `emit_early` kwarg in the
#   `sum` function below.
struct WindowOp{T, Op, AlwaysTicks} <: StatefulUnaryNodeOp{T, AlwaysTicks}
    window::Int64
end

function Base.show(io::IO, op::WindowOp{T, Op}) where {T, Op}
    return print(io, "$(typeof(op).name.name){$T, $Op}($(op.window))")
end

struct WindowOpState{T, Op} <: NodeEvaluationState
    window_state::FixedWindowAssociativeOp{T, Op}
end

function create_evaluation_state(::Tuple{Node}, op::WindowOp{T, Op}) where {T, Op}
    return WindowOpState(FixedWindowAssociativeOp{T, Op}(op.window))
end

# emit_early = true
function operator(::WindowOp{T, Op, true}, state::WindowOpState{T}, x::T) where {T, Op}
    update_state!(state.window_state, x)
    return window_value(state.window_state)
end

# emit_early = false
function operator(::WindowOp{T, Op, false}, state::WindowOpState{T}, x::T) where {T, Op}
    update_state!(state.window_state, x)
    should_tick = window_full(state.window_state)
    return (window_value(state.window_state), should_tick)
end

function sum(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowOp{value_type(x), +, emit_early}(window))
end

function prod(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowOp{value_type(x), *, emit_early}(window))
end
