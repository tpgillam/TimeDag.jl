"""
Wrap a value into a data object of the given type, for use with associative combinations.
"""
_wrap(::Type{T}, x::T) where {T} = x

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

# Operator accumulated from inception.
struct InceptionOp{T,Data,CombineOp,ExtractOp} <: UnaryNodeOp{T} end

always_ticks(op::InceptionOp) = _unfiltered(op)
time_agnostic(::InceptionOp) = true

mutable struct InceptionOpState{Data} <: NodeEvaluationState
    initialised::Bool
    data::Data
    # `data` will be uninitialised until the first call.
    InceptionOpState{Data}() where {Data} = new{Data}(false)
end

# TODO Could have more than one parent.
function create_operator_evaluation_state(
    ::Tuple{Node}, ::InceptionOp{T,Data}
) where {T,Data}
    return InceptionOpState{Data}()
end

function operator!(
    op::InceptionOp{T,Data,CombineOp,ExtractOp}, state::InceptionOpState{Data}, x
) where {T,Data,CombineOp,ExtractOp}
    if !state.initialised
        state.data = _wrap(Data, x)
        state.initialised = true
    else
        state.data = CombineOp(state.data, _wrap(Data, x))
    end
    return if always_ticks(op)
        # Deal with the case where we always emit.
        ExtractOp(state.data)
    elseif _unfiltered(op) || _should_tick(op, state.data)
        Maybe(ExtractOp(state.data))
    else
        Maybe{T}()
    end
end

# Windowed associative binary operator, potentially emitting early before the window is
# full.
struct WindowOp{T,Data,CombineOp,ExtractOp,EmitEarly} <: UnaryNodeOp{T}
    window::Int64
end

"""Whether or not this window op is set to emit with a non-full window."""
function _emit_early(
    ::WindowOp{T,Data,CombineOp,ExtractOp,true}
) where {T,Data,CombineOp,ExtractOp}
    return true
end
function _emit_early(
    ::WindowOp{T,Data,CombineOp,ExtractOp,false}
) where {T,Data,CombineOp,ExtractOp}
    return false
end

always_ticks(op::WindowOp) = _emit_early(op) && _unfiltered(op)
time_agnostic(::WindowOp) = true

mutable struct WindowOpState{Data} <: NodeEvaluationState
    window_state::FixedWindowAssociativeOp{Data}
end

function create_operator_evaluation_state(
    ::Tuple{Node}, op::WindowOp{T,Data,CombineOp}
) where {T,Data,CombineOp}
    return WindowOpState{Data}(FixedWindowAssociativeOp{Data,CombineOp}(op.window))
end

function operator!(
    op::WindowOp{T,Data,CombineOp,ExtractOp}, state::WindowOpState{Data}, x
) where {T,Data,CombineOp,ExtractOp}
    update_state!(state.window_state, _wrap(Data, x))
    if always_ticks(op)
        # Deal with the case where we always emit.
        return ExtractOp(window_value(state.window_state))
    end

    ready = _emit_early(op) || window_full(state.window_state)
    if !ready
        return Maybe{T}()
    end

    data = window_value(state.window_state)
    return if _unfiltered(op) || _should_tick(op, data)
        Maybe(ExtractOp(data))
    else
        Maybe{T}()
    end
end

# Sum, cumulative over time.
const Sum{T} = InceptionOp{T,T,+,identity}
_unfiltered(::Sum) = true
Base.show(io::IO, ::Sum{T}) where {T} = print(io, "Sum{$T}")
function Base.sum(x::Node)
    _is_constant(x) && return x
    return obtain_node((x,), Sum{value_type(x)}())
end

# Sum over fixed window.
const WindowSum{T,EmitEarly} = WindowOp{T,T,+,identity,EmitEarly}
_unfiltered(::WindowSum) = true
Base.show(io::IO, op::WindowSum{T}) where {T} = print(io, "WindowSum{$T}($(op.window))")
function Base.sum(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowSum{value_type(x),emit_early}(window))
end

# Product, cumulative over time.
const Prod{T} = InceptionOp{T,T,*,identity}
_unfiltered(::Prod) = true
Base.show(io::IO, ::Prod{T}) where {T} = print(io, "Prod{$T}")
function Base.prod(x::Node)
    _is_constant(x) && return x
    return obtain_node((x,), Prod{value_type(x)}())
end

# Product over fixed window.
const WindowProd{T,EmitEarly} = WindowOp{T,T,*,identity,EmitEarly}
_unfiltered(::WindowProd) = true
Base.show(io::IO, op::WindowProd{T}) where {T} = print(io, "WindowProd{$T}($(op.window))")
function Base.prod(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowProd{value_type(x),emit_early}(window))
end

# Mean, cumulative over time.
# In order to be numerically stable, use a generalisation of Welford's algorithm.
# Disable formatting: https://github.com/domluna/JuliaFormatter.jl/issues/480
#! format: off
const MeanData{T} = @NamedTuple{n::Int64, mean::T} where {T}
#! format: on
_wrap(::Type{MeanData{T}}, x) where {T} = MeanData{T}((1, x))
function _combine(state_a::MeanData{T}, state_b::MeanData{T})::MeanData{T} where {T}
    na = state_a.n
    nb = state_b.n
    nc = na + nb
    return MeanData{T}((n=nc, mean=state_a.mean * (na / nc) + state_b.mean * (nb / nc)))
end
_extract(data::MeanData) = data.mean
const Mean{T} = InceptionOp{T,MeanData{T},_combine,_extract}
_unfiltered(::Mean) = true
Base.show(io::IO, ::Mean{T}) where {T} = print(io, "Mean{$T}")
function Statistics.mean(x::Node)
    _is_constant(x) && return x
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), Mean{T}())
end

# Mean over fixed window.
const WindowMean{T,EmitEarly} = WindowOp{T,MeanData{T},_combine,_extract,EmitEarly}
_unfiltered(::WindowMean) = true
Base.show(io::IO, op::WindowMean{T}) where {T} = print(io, "WindowMean{$T}($(op.window))")
function Statistics.mean(x::Node, window::Int; emit_early::Bool=false)
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), WindowMean{T,emit_early}(window))
end

# Variance, cumulative over time.
# In order to be numerically stable, use a generalisation of Welford's algorithm.
# Disable formatting: https://github.com/domluna/JuliaFormatter.jl/issues/480
#! format: off
const VarData{T} = @NamedTuple{n::Int64, mean::T, s::T} where {T}
#! format: on
_wrap(::Type{VarData{T}}, x) where {T} = VarData{T}((1, x, 0))
function _combine(state_a::VarData{T}, state_b::VarData{T})::VarData{T} where {T}
    na = state_a.n
    nb = state_b.n
    nc = na + nb

    μa = state_a.mean
    μb = state_b.mean
    μc = state_a.mean * (na / nc) + state_b.mean * (nb / nc)

    sa = state_a.s
    sb = state_b.s

    return VarData{T}((n=nc, mean=μc, s=(sa + sb) + nb * (μb - μa) * (μb - μc)))
end
_extract(data::VarData) = data.s / (data.n - 1)
const Var{T} = InceptionOp{T,VarData{T},_combine,_extract}
_should_tick(::Var, data::VarData) = data.n > 1
Base.show(io::IO, ::Var{T}) where {T} = print(io, "Var{$T}")
function Statistics.var(x::Node)
    _is_constant(x) && return x
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), Var{T}())
end

# Variance over fixed window.
const WindowVar{T,EmitEarly} = WindowOp{T,VarData{T},_combine,_extract,EmitEarly}
_should_tick(::WindowVar, data::VarData) = data.n > 1
Base.show(io::IO, op::WindowVar{T}) where {T} = print(io, "WindowVar{$T}($(op.window))")
function Statistics.var(x::Node, window::Int; emit_early::Bool=false)
    window >= 2 || throw(ArgumentError("Got window=$window, but should be at least 2"))
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), WindowVar{T,emit_early}(window))
end

# Standard deviation.
Statistics.std(x::Node) = sqrt(var(x))
function Statistics.std(x::Node, window::Int; emit_early::Bool=false)
    return sqrt(var(x, window; emit_early))
end
