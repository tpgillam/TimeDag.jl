"""
    _wrap(::Type{T}, x...)

Wrap value(s) into a data object of the given type, for use with associative combinations.

The default implementation handles the identity case, and also common conversions where
possible (calling single-argument constructor). A custom method should be added when
needed for user-defined types.
"""
_wrap(::Type{T}, x::T) where {T} = x
_wrap(::Type{T}, x::S) where {S,T} = T(x)

"""
    _unfiltered(op) -> Bool

Returns true iff `_should_tick` will always return true.
"""
_unfiltered(::NodeOp) = false

"""
    _should_tick(op, data) -> Bool

This should be defined for any op that does not have `_unfiltered(op)` returning true.
The return value determines whether a knot should be emitted for this value.
"""
function _should_tick end

"""
    _combine(op, data_1, data_2) -> Data

This should be defined for all inception and windowed ops. Given two data objects, combine
them into a new data object.
"""
function _combine end

"""
    _update(op, data_1, x...) -> Data

Given a data object, and a new observation (of potentially multiple arguments), generate a
new data field.

If only creating an `InceptionOp`, it is sufficient to define this instead of `_combine`.
By default this will use `_wrap` and `_combine`.
"""
_update(op, data_1, x...) = _combine(op, data_1, _wrap(_data_type(op), x...))

"""
    _extract(op, data) -> value

This should be defined for all inception and windowed ops. Given some data object, it should
compute the appropriate output value for the node.
"""
function _extract end

"""
    _data_type(op)

Return the type of data used for the given op.
"""
function _data_type end

"""Unary operator accumulated from inception."""
abstract type UnaryInceptionOp{T,Data} <: UnaryNodeOp{T} end

"""Binary operator accumulated from inception."""
abstract type BinaryInceptionOp{T,Data,A} <: BinaryNodeOp{T,A} end

const InceptionOp{T,Data} = Union{UnaryInceptionOp{T,Data},BinaryInceptionOp{T,Data}}
_data_type(::InceptionOp{T,Data}) where {T,Data} = Data

always_ticks(op::InceptionOp) = _unfiltered(op)
time_agnostic(::InceptionOp) = true

mutable struct InceptionOpState{Data} <: NodeEvaluationState
    initialised::Bool
    data::Data
    # `data` will be uninitialised until the first call.
    InceptionOpState{Data}() where {Data} = new{Data}(false)
end

function create_operator_evaluation_state(
    ::Tuple{Node}, ::UnaryInceptionOp{T,Data}
) where {T,Data}
    return InceptionOpState{Data}()
end

function create_operator_evaluation_state(
    ::Tuple{Node,Node}, ::BinaryInceptionOp{T,Data}
) where {T,Data}
    return InceptionOpState{Data}()
end

function operator!(
    op::InceptionOp{T,Data}, state::InceptionOpState{Data}, x...
) where {T,Data}
    if !state.initialised
        state.data = _wrap(Data, x...)
        state.initialised = true
    else
        state.data = _update(op, state.data, x...)
    end
    return if always_ticks(op)
        # Deal with the case where we always emit.
        _extract(op, state.data)
    elseif _unfiltered(op) || _should_tick(op, state.data)
        Maybe(_extract(op, state.data))
    else
        Maybe{T}()
    end
end

"""
Windowed associative binary operator, potentially emitting early before the window is full.
"""
abstract type UnaryWindowOp{T,Data,EmitEarly} <: UnaryNodeOp{T} end
abstract type BinaryWindowOp{T,Data,EmitEarly,A} <: BinaryNodeOp{T,A} end

const WindowOp{T,Data,EmitEarly} = Union{
    UnaryWindowOp{T,Data,EmitEarly},BinaryWindowOp{T,Data,EmitEarly}
}
_data_type(::WindowOp{T,Data}) where {T,Data} = Data

"""
    _window(::WindowOp) -> Int64

Return the number of knots in the window for the specified op.
The default implementation expects a field called `window` on the op structure.
"""
_window(op::WindowOp) = op.window

"""Whether or not this window op is set to emit with a non-full window."""
_emit_early(::WindowOp{T,Data,true}) where {T,Data} = true
_emit_early(::WindowOp{T,Data,false}) where {T,Data} = false

always_ticks(op::WindowOp) = _emit_early(op) && _unfiltered(op)
time_agnostic(::WindowOp) = true

# FIXME profile performance impact of not templating this state on the op. Could be high.
mutable struct WindowOpState{Data} <: NodeEvaluationState
    window_state::FixedWindowAssociativeOp{Data}
end

function create_operator_evaluation_state(::Tuple{Node}, op::UnaryWindowOp)
    return create_operator_evaluation_state(op)
end

function create_operator_evaluation_state(::Tuple{Node,Node}, op::BinaryWindowOp)
    return create_operator_evaluation_state(op)
end

function create_operator_evaluation_state(op::WindowOp{T,Data}) where {T,Data}
    return WindowOpState{Data}(
        FixedWindowAssociativeOp{Data,(x, y) -> _combine(op, x, y)}(_window(op))
    )
end

function operator!(op::WindowOp{T,Data}, state::WindowOpState{Data}, x...) where {T,Data}
    update_state!(state.window_state, _wrap(Data, x...))
    if always_ticks(op)
        # Deal with the case where we always emit.
        return _extract(op, window_value(state.window_state))
    end

    ready = _emit_early(op) || window_full(state.window_state)
    if !ready
        return Maybe{T}()
    end

    data = window_value(state.window_state)
    return if _unfiltered(op) || _should_tick(op, data)
        Maybe(_extract(op, data))
    else
        Maybe{T}()
    end
end

"""
Time-windowed associative binary operator, potentially emitting early before the window is
full.
"""
abstract type UnaryTWindowOp{T,Data,EmitEarly} <: UnaryNodeOp{T} end
abstract type BinaryTWindowOp{T,Data,EmitEarly,A} <: BinaryNodeOp{T,A} end

const TWindowOp{T,Data,EmitEarly} = Union{
    UnaryTWindowOp{T,Data,EmitEarly},BinaryTWindowOp{T,Data,EmitEarly}
}
_data_type(::TWindowOp{T,Data}) where {T,Data} = Data

"""
    _window(::TWindowOp) -> Millisecond

Return the time duration of the window for the specified op.
The default implementation expects a field called `window` on the op structure.
"""
_window(op::TWindowOp) = op.window

"""Whether or not this window op is set to emit with a non-full window."""
_emit_early(::TWindowOp{T,Data,true}) where {T,Data} = true
_emit_early(::TWindowOp{T,Data,false}) where {T,Data} = false

always_ticks(op::TWindowOp) = _emit_early(op) && _unfiltered(op)
time_agnostic(::TWindowOp) = false

mutable struct TWindowOpState{Data,Op} <: NodeEvaluationState
    window_state::TimeWindowAssociativeOp{Data,Op,Op,DateTime,Millisecond}
end

function create_operator_evaluation_state(::Tuple{Node}, op::UnaryTWindowOp)
    return create_operator_evaluation_state(op)
end

function create_operator_evaluation_state(::Tuple{Node,Node}, op::BinaryTWindowOp)
    return create_operator_evaluation_state(op)
end

function create_operator_evaluation_state(op::TWindowOp{T,Data}) where {T,Data}
    f(x, y) = _combine(op, x, y)
    return TWindowOpState{Data,f}(TimeWindowAssociativeOp{Data,f,f,DateTime}(_window(op)))
end

function operator!(
    op::TWindowOp{T,Data}, state::TWindowOpState{Data}, t::DateTime, x...
) where {T,Data}
    update_state!(state.window_state, t, _wrap(Data, x...))
    if always_ticks(op)
        # Deal with the case where we always emit.
        return _extract(op, window_value(state.window_state))
    end

    ready = _emit_early(op) || window_full(state.window_state)
    if !ready
        return Maybe{T}()
    end

    data = window_value(state.window_state)
    return if _unfiltered(op) || _should_tick(op, data)
        Maybe(_extract(op, data))
    else
        Maybe{T}()
    end
end
