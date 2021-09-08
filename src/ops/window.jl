"""
Wrap a value into a data object of the given type, for use with associative combinations.
"""
_wrap(::Type{T}, x::T) where {T} = x

# Operator accumulated from inception.
struct InceptionOp{T, Data, CombineOp, ExtractOp} <: StatefulUnaryNodeOp{T, true}
end

mutable struct InceptionOpState{Data} <: NodeEvaluationState
    initialised::Bool
    data::Data
    # `data` will be uninitialised until the first call.
    InceptionOpState{Data}() where {Data} = new{Data}(false)
end

function create_evaluation_state(::Tuple{Node}, ::InceptionOp{T, Data}) where {T, Data}
    return InceptionOpState{Data}()
end

function operator(
    ::InceptionOp{T, Data, CombineOp, ExtractOp},
    state::InceptionOpState{Data},
    x
) where {T, Data, CombineOp, ExtractOp}
    if !state.initialised
        state.data = _wrap(Data, x)
        state.initialised = true
    else
        state.data = CombineOp(state.data, _wrap(Data, x))
    end
    return ExtractOp(state.data)
end

# Windowed associative binary operator, potentially emitting early before the window is
# full.
# Note that we are equating the `AlwaysTicks` parameter with the `emit_early` kwarg in the
#   API functions below.
struct WindowOp{
    T,
    Data,
    CombineOp,
    ExtractOp,
    AlwaysTicks
} <: StatefulUnaryNodeOp{T, AlwaysTicks}
    window::Int64
end

mutable struct WindowOpState{Data} <: NodeEvaluationState
    window_state::FixedWindowAssociativeOp{Data}
end

function create_evaluation_state(
    ::Tuple{Node},
    op::WindowOp{T, Data, CombineOp}
) where {T, Data, CombineOp}
    return WindowOpState{Data}(FixedWindowAssociativeOp{Data, CombineOp}(op.window))
end

# emit_early = true
function operator(
    ::WindowOp{T, Data, CombineOp, ExtractOp, true},
    state::WindowOpState{Data},
    x
) where {T, Data, CombineOp, ExtractOp}
    update_state!(state.window_state, _wrap(Data, x))
    return ExtractOp(window_value(state.window_state))
end

# emit_early = false
function operator(
    ::WindowOp{T, Data, CombineOp, ExtractOp, false},
    state::WindowOpState{Data},
    x
) where {T, Data, CombineOp, ExtractOp}
    update_state!(state.window_state, _wrap(Data, x))
    should_tick = window_full(state.window_state)
    return (ExtractOp(window_value(state.window_state)), should_tick)
end


# Sum, cumulative over time.
const Sum{T} = InceptionOp{T, T, +, identity}
Base.show(io::IO, ::Sum{T}) where {T} = print(io, "Sum{$T}")
function sum(x::Node)
    _is_constant(x) && return x
    return obtain_node((x,), Sum{value_type(x)}())
end

# Sum over fixed window.
const WindowSum{T, AlwaysTicks} = WindowOp{T, T, +, identity, AlwaysTicks}
Base.show(io::IO, op::WindowSum{T}) where {T} = print(io, "WindowSum{$T}($(op.window))")
function sum(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowSum{value_type(x), emit_early}(window))
end


# Product, cumulative over time.
const Prod{T} = InceptionOp{T, T, *, identity}
Base.show(io::IO, ::Prod{T}) where {T} = print(io, "Prod{$T}")
function prod(x::Node)
    _is_constant(x) && return x
    return obtain_node((x,), Prod{value_type(x)}())
end

# Product over fixed window.
const WindowProd{T, AlwaysTicks} = WindowOp{T, T, *, identity, AlwaysTicks}
Base.show(io::IO, op::WindowProd{T}) where {T} = print(io, "WindowProd{$T}($(op.window))")
function prod(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowProd{value_type(x), emit_early}(window))
end


# Mean, cumulative over time.
# In order to be numerically stable, use a generalisation of Welford's algorithm.
const MeanData{T} = @NamedTuple{n::Int64, mean::T} where {T}
_wrap(::Type{MeanData{T}}, x) where {T} = MeanData{T}((1, x))
function _combine(state_a::MeanData{T}, state_b::MeanData{T})::MeanData{T} where {T}
    na = state_a.n
    nb = state_b.n
    nc = na + nb
    return MeanData{T}((
        n=nc,
        mean=state_a.mean * (na / nc) + state_b.mean * (nb / nc),
    ))
end
_extract(data::MeanData) = data.mean
const Mean{T} = InceptionOp{T, MeanData{T}, _combine, _extract}
Base.show(io::IO, ::Mean{T}) where {T} = print(io, "Mean{$T}")
function mean(x::Node)
    _is_constant(x) && return x
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), Mean{T}())
end
