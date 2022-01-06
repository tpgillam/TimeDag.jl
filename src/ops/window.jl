"""
    _wrap(::Type{T}, x...)

Wrap value(s) into a data object of the given type, for use with associative combinations.
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
    _window(window_op) -> Int64

Return the window for the specified op.
The default implementation expects a field called `window` on the op structure.
"""
_window(op::WindowOp) = op.window

"""Whether or not this window op is set to emit with a non-full window."""
function _emit_early(::WindowOp{T,Data,true}) where {T,Data}
    return true
end
function _emit_early(::WindowOp{T,Data,false}) where {T,Data}
    return false
end

always_ticks(op::WindowOp) = _emit_early(op) && _unfiltered(op)
time_agnostic(::WindowOp) = true

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

# Sum, cumulative over time.
struct Sum{T} <: UnaryInceptionOp{T,T} end
_unfiltered(::Sum) = true
_combine(::Sum, x, y) = x + y
_extract(::Sum, data) = data
Base.show(io::IO, ::Sum{T}) where {T} = print(io, "Sum{$T}")
"""
    sum(x::Node) -> Node

Create a node which ticks when `x` ticks, with values of the cumulative sum of `x`.
"""
function Base.sum(x::Node)
    _is_constant(x) && return x
    return obtain_node((x,), Sum{value_type(x)}())
end

# Sum over fixed window.
struct WindowSum{T,EmitEarly} <: UnaryWindowOp{T,T,EmitEarly}
    window::Int64
end
_unfiltered(::WindowSum) = true
_combine(::WindowSum, x, y) = x + y
_extract(::WindowSum, data) = data
Base.show(io::IO, op::WindowSum{T}) where {T} = print(io, "WindowSum{$T}($(_window(op)))")

"""
    sum(x::Node, window::Int; emit_early::Bool=false) -> Node

Create a node of the rolling sum of `x` over the last `window` knots.

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.
"""
function Base.sum(x::Node, window::Int; emit_early::Bool=false)
    return obtain_node((x,), WindowSum{value_type(x),emit_early}(window))
end

# Product, cumulative over time.
struct Prod{T} <: UnaryInceptionOp{T,T} end
_unfiltered(::Prod) = true
_combine(::Prod, x, y) = x * y
_extract(::Prod, data) = data
Base.show(io::IO, ::Prod{T}) where {T} = print(io, "Prod{$T}")
"""
    prod(x::Node) -> Node

Create a node which ticks when `x` ticks, with values of the cumulative product of `x`.
"""
function Base.prod(x::Node)
    _is_constant(x) && return x
    return obtain_node((x,), Prod{value_type(x)}())
end

# Product over fixed window.
struct WindowProd{T,EmitEarly} <: UnaryWindowOp{T,T,EmitEarly}
    window::Int64
end
_unfiltered(::WindowProd) = true
_combine(::WindowProd, x, y) = x * y
_extract(::WindowProd, data) = data
Base.show(io::IO, op::WindowProd{T}) where {T} = print(io, "WindowProd{$T}($(_window(op)))")
"""
    prod(x::Node, window::Int; emit_early::Bool=false) -> Node

Create a node of the rolling product of `x` over the last `window` knots.

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.
"""
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
struct Mean{T} <: UnaryInceptionOp{T,MeanData{T}} end
_unfiltered(::Mean) = true
function _combine(state_a::MeanData{T}, state_b::MeanData{T}) where {T}
    na = state_a.n
    nb = state_b.n
    nc = na + nb
    return MeanData{T}((n=nc, mean=state_a.mean * (na / nc) + state_b.mean * (nb / nc)))
end
_combine(::Mean, x::MeanData, y::MeanData) = _combine(x, y)
_extract(::Mean, data::MeanData) = data.mean
Base.show(io::IO, ::Mean{T}) where {T} = print(io, "Mean{$T}")
"""
    mean(x::Node) -> Node

Create a node which ticks when `x` ticks, with values of the running mean of `x`.
"""
function Statistics.mean(x::Node)
    _is_constant(x) && return x
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), Mean{T}())
end

# Mean over fixed window.
struct WindowMean{T,EmitEarly} <: UnaryWindowOp{T,MeanData{T},EmitEarly}
    window::Int64
end
_unfiltered(::WindowMean) = true
_combine(::WindowMean, x::MeanData, y::MeanData) = _combine(x, y)
_extract(::WindowMean, data::MeanData) = data.mean
Base.show(io::IO, op::WindowMean{T}) where {T} = print(io, "WindowMean{$T}($(_window(op)))")
"""
    mean(x::Node, window::Int; emit_early::Bool=false) -> Node

Create a node of the rolling mean of `x` over the last `window` knots.

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.
"""
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
struct Var{T,corrected} <: UnaryInceptionOp{T,VarData{T}} end
_should_tick(::Var, data::VarData) = data.n > 1
function _combine(state_a::VarData{T}, state_b::VarData{T}) where {T}
    na = state_a.n
    nb = state_b.n
    nc = na + nb

    μa = state_a.mean
    μb = state_b.mean
    μc = μa * (na / nc) + μb * (nb / nc)

    sa = state_a.s
    sb = state_b.s

    return VarData{T}((n=nc, mean=μc, s=(sa + sb) + nb * (μb - μa) * (μb - μc)))
end
_combine(::Var, x::VarData, y::VarData) = _combine(x, y)
_extract(::Var{T,true}, data::VarData) where {T} = data.s / (data.n - 1)
_extract(::Var{T,false}, data::VarData) where {T} = data.s / data.n
Base.show(io::IO, ::Var{T}) where {T} = print(io, "Var{$T}")
"""
    var(x::Node; corrected::Bool=true) -> Node

Create a node which ticks when `x` ticks, with values of the running variance of `x`.

This is equivalent to a sample variance over the `n` values of `x` observed at and before a
given time. If `corrected` is `true` (the default), we normalise by `n-1`, otherwise we
normalise by `n`.
"""
function Statistics.var(x::Node; corrected::Bool=true)
    _is_constant(x) && throw(ArgumentError("Cannot compute variance of constant $x"))
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), Var{T,corrected}())
end

# Variance over fixed window.
struct WindowVar{T,Corrected,EmitEarly} <: UnaryWindowOp{T,VarData{T},EmitEarly}
    window::Int64
end
_should_tick(::WindowVar, data::VarData) = data.n > 1
_combine(::WindowVar, x::VarData, y::VarData) = _combine(x, y)
_extract(::WindowVar{T,true}, data::VarData) where {T} = data.s / (data.n - 1)
_extract(::WindowVar{T,false}, data::VarData) where {T} = data.s / data.n
Base.show(io::IO, op::WindowVar{T}) where {T} = print(io, "WindowVar{$T}($(_window(op)))")
"""
    var(x::Node, window::Int; emit_early::Bool=false, corrected::Bool=true) -> Node

Create a node of the rolling variance of `x` over the last `window` knots.

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.

This is equivalent to a sample variance over the `n` values of `x` (capped at `window`),
observed at and before a given time. If `corrected` is `true` (the default), we normalise by
`n-1`, otherwise we normalise by `n`.
"""
function Statistics.var(x::Node, window::Int; emit_early::Bool=false, corrected::Bool=true)
    _is_constant(x) && throw(ArgumentError("Cannot compute variance of constant $x"))
    window >= 2 || throw(ArgumentError("Got window=$window, but should be at least 2"))
    T = output_type(/, value_type(x), Int)
    return obtain_node((x,), WindowVar{T,corrected,emit_early}(window))
end

# Standard deviation.
"""
    std(x::Node; corrected::Bool=true) -> Node

Create a node which ticks when `x` ticks, with values of the running standard deviation of
`x`.

This is equivalent to `sqrt(var(x; corrected))`.
"""
Statistics.std(x::Node; corrected::Bool=true) = sqrt(var(x; corrected))

"""
    std(x::Node, window::Int; emit_early::Bool=false, corrected::Bool=true) -> Node

Create a node of the rolling standard deviation of `x` over the last `window` knots.

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.

This is equivalent to `sqrt(var(x; emit_early, corrected))`.
"""
function Statistics.std(x::Node, window::Int; emit_early::Bool=false, corrected::Bool=true)
    return sqrt(var(x, window; emit_early, corrected))
end

# Covariance, cumulative over time.
# Disable formatting: https://github.com/domluna/JuliaFormatter.jl/issues/480
#! format: off
const CovData{T} = @NamedTuple{n::Int64, mean_x::T, mean_y::T, c::T} where {T}
#! format: on
_wrap(::Type{CovData{T}}, x, y) where {T} = CovData{T}((1, x, y, 0))
struct Cov{T,corrected,A} <: BinaryInceptionOp{T,CovData{T},A} end
_should_tick(::Cov, data::CovData) = data.n > 1
function _combine(state_a::CovData{T}, state_b::CovData{T}) where {T}
    na = state_a.n
    nb = state_b.n
    nc = na + nb

    μxa = state_a.mean_x
    μxb = state_b.mean_x
    μxc = μxa * (na / nc) + μxb * (nb / nc)

    μya = state_a.mean_y
    μyb = state_b.mean_y
    μyc = μya * (na / nc) + μyb * (nb / nc)

    ca = state_a.c
    cb = state_b.c
    # FIXME This is speculation - do the algebra to check this!
    cc = (ca + cb) + nb * (μxb - μxa) * (μyb - μyc)

    return CovData{T}((n=nc, mean_x=μxc, mean_y=μyc, c=cc))
end
_combine(::Cov, x::CovData, y::CovData) = _combine(x, y)
_extract(::Cov{T,true}, data::CovData) where {T} = data.c / (data.n - 1)
_extract(::Cov{T,false}, data::CovData) where {T} = data.c / data.n
Base.show(io::IO, ::Cov{T}) where {T} = print(io, "Cov{$T}")
"""
    cov(x, y[, alignment]; corrected::Bool=true) -> Node

Create a node which ticks with values of the running covariance of `x` and `y`.

The specified `alignment` controls the behaviour when `x` and `y` tick at different times,
as per the documentation in [Alignment](@ref). When not specified, it defaults to
[`UNION`](@ref).

This is equivalent to a sample covariance over the `n` values of `(x, y)` pairs observed at
and before a given time. If `corrected` is `true` (the default), we normalise by `n-1`,
otherwise we normalise by `n`.
"""
function Statistics.cov(x, y, ::A; corrected::Bool=true) where {A<:Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    if _is_constant(x) && _is_constant(y)
        throw(ArgumentError("Cannot compute variance of constants $x and $y"))
    end
    T = output_type(/, output_type(*, value_type(x), value_type(y)), Int)
    return obtain_node((x, y), Cov{T,corrected,A}())
end
function Statistics.cov(x::Node, y::Node; corrected::Bool=true)
    return cov(x, y, DEFAULT_ALIGNMENT; corrected)
end
Statistics.cov(x::Node, y; corrected::Bool=true) = cov(x, y, DEFAULT_ALIGNMENT; corrected)
Statistics.cov(x, y::Node; corrected::Bool=true) = cov(x, y, DEFAULT_ALIGNMENT; corrected)

# Covariance over fixed window.
struct WindowCov{T,Corrected,EmitEarly,A} <: BinaryWindowOp{T,CovData{T},EmitEarly,A}
    window::Int64
end
_should_tick(::WindowCov, data::CovData) = data.n > 1
_combine(::WindowCov, x::CovData, y::CovData) = _combine(x, y)
_extract(::WindowCov{T,true}, data::CovData) where {T} = data.c / (data.n - 1)
_extract(::WindowCov{T,false}, data::CovData) where {T} = data.c / data.n
Base.show(io::IO, op::WindowCov{T}) where {T} = print(io, "WindowCov{$T}($(_window(op)))")

"""
    cov(x, y, window::Int[, alignment]; emit_early=false, corrected=true) -> Node

Create a node of the rolling covariance of `x` and `y` over the last `window` knots.

The specified `alignment` controls the behaviour when `x` and `y` tick at different times,
as per the documentation in [Alignment](@ref). When not specified, it defaults to
[`UNION`](@ref).

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.

This is equivalent to a sample covariance over the `n` values of `(x, y)` pairs observed at
and before a given time, with `n` capped at `window`. If `corrected` is `true` (the
default), we normalise by `n-1`, otherwise we normalise by `n`.
"""
function Statistics.cov(
    x, y, window::Int, ::A; emit_early::Bool=false, corrected::Bool=true
) where {A<:Alignment}
    window >= 2 || throw(ArgumentError("Got window=$window, but should be at least 2"))
    x = _ensure_node(x)
    y = _ensure_node(y)
    if _is_constant(x) && _is_constant(y)
        throw(ArgumentError("Cannot compute covariance of constants $x and $y"))
    end
    T = output_type(/, output_type(*, value_type(x), value_type(y)), Int)
    return obtain_node((x, y), WindowCov{T,corrected,emit_early,A}(window))
end
function Statistics.cov(
    x::Node, y::Node, window::Int; emit_early::Bool=false, corrected::Bool=true
)
    return cov(x, y, window, DEFAULT_ALIGNMENT; emit_early, corrected)
end
function Statistics.cov(
    x::Node, y, window::Int; emit_early::Bool=false, corrected::Bool=true
)
    return cov(x, y, window, DEFAULT_ALIGNMENT; emit_early, corrected)
end
function Statistics.cov(
    x, y::Node, window::Int; emit_early::Bool=false, corrected::Bool=true
)
    return cov(x, y, window, DEFAULT_ALIGNMENT; emit_early, corrected)
end

# Covariance matrix.
abstract type AbstractCovMatrixData{T} end

"""State for an n-dimensional covariance matrix."""
struct CovMatrixData{T} <: AbstractCovMatrixData{T}
    n::Int64
    μ::Vector{T}
    c::Matrix{T}
end

function _wrap(::Type{CovMatrixData{T}}, x::AbstractVector) where {T}
    return CovMatrixData{T}(1, Vector(x), zeros(eltype(x), size(x, 1), size(x, 1)))
end

"""State for an n-dimensional covariance matrix of statically known dimension."""
struct CovMatrixStaticData{T,N,L} <: AbstractCovMatrixData{T}
    n::Int64
    μ::SVector{N,T}
    c::SMatrix{N,N,T,L}
end

function _wrap(::Type{CovMatrixStaticData{T,N,L}}, x::SVector{N}) where {T,N,L}
    return CovMatrixStaticData{T,N,L}(1, x, zeros(SMatrix{N,N,T,L}))
end

function _combine(a::Data, b::Data) where {Data<:AbstractCovMatrixData}
    n = a.n + b.n
    μ = @. a.μ * (a.n / n) + b.μ * (b.n / n)
    # TODO wrap c in `Hermitian` / only update one triangle?
    c = (a.c .+ b.c) .+ b.n .* (b.μ .- a.μ) * (b.μ .- μ)'
    return Data(n, μ, c)
end

# Static covariance matrix node ops.
struct CovMatrixStatic{N,L,T,corrected} <:
       UnaryInceptionOp{SMatrix{N,N,T,L},CovMatrixStaticData{T,N,L}} end
_should_tick(::CovMatrixStatic, data::CovMatrixStaticData) = data.n > 1
_combine(::CovMatrixStatic, x::CovMatrixStaticData, y::CovMatrixStaticData) = _combine(x, y)
function _extract(::CovMatrixStatic{N,L,T,true}, data::CovMatrixStaticData) where {N,L,T}
    return data.c ./ (data.n - 1)
end
function _extract(::CovMatrixStatic{N,L,T,false}, data::CovMatrixStaticData) where {N,L,T}
    return data.c ./ data.n
end
function Base.show(io::IO, ::CovMatrixStatic{N,L,T}) where {N,L,T}
    return print(io, "CovMatrixStatic{$T,$(N)x$(N)}")
end

"""
    cov(x::Node{<:AbstractVector}; corrected::Bool=true) -> Node

Create a node which ticks with values of the running covariance of `x`.

!!! warning
    If the values of `x` change shape over time, this node will throw an exception during
    evaluation.
"""
function Statistics.cov(
    x::Node{<:StaticVector{N,T}}; corrected::Bool=true
) where {N,T<:Number}
    _is_constant(x) && throw(ArgumentError("Cannot compute covariance of constant $x"))
    Out = output_type(/, T, Int)
    return obtain_node((x,), CovMatrixStatic{N,N * N,Out,corrected}())
end

# An n-dimensional covariance matrix over a fixed window.
struct WindowCovMatrixStatic{N,L,T,Corrected,EmitEarly} <:
       UnaryWindowOp{SMatrix{N,N,T,L},CovMatrixStaticData{T,N,L},EmitEarly}
    window::Int64
end
_should_tick(::WindowCovMatrixStatic, data::CovMatrixStaticData) = data.n > 1
function _combine(::WindowCovMatrixStatic, x::CovMatrixStaticData, y::CovMatrixStaticData)
    return _combine(x, y)
end
function _extract(
    ::WindowCovMatrixStatic{N,L,T,true}, data::CovMatrixStaticData
) where {N,L,T}
    return data.c ./ (data.n - 1)
end
function _extract(
    ::WindowCovMatrixStatic{N,L,T,false}, data::CovMatrixStaticData
) where {N,L,T}
    return data.c ./ data.n
end
function Base.show(io::IO, op::WindowCovMatrixStatic{N,L,T}) where {N,L,T}
    return print(io, "WindowCovMatrixStatic{$T,$(N)x$(N)}($(_window(op)))")
end
"""
    cov(x::Node{<:AbstractVector}, window::Int; corrected::Bool=true) -> Node

Create a node of the rolling covariance of `x` over the last `window` knots.

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.

!!! warning
    If the values of `x` change shape over time, this node will throw an exception during
    evaluation.
"""
function Statistics.cov(
    x::Node{<:StaticVector{N,T}}, window::Int; emit_early::Bool=false, corrected::Bool=true
) where {N,T<:Number}
    _is_constant(x) && throw(ArgumentError("Cannot compute variance of constant $x"))
    window >= 2 || throw(ArgumentError("Got window=$window, but should be at least 2"))
    Out = output_type(/, T, Int)
    return obtain_node(
        (x,), WindowCovMatrixStatic{N,N * N,Out,corrected,emit_early}(window)
    )
end

# Non-static covariance matrix nodes.
struct CovMatrix{T,corrected} <: UnaryInceptionOp{Matrix{T},CovMatrixData{T}} end
_should_tick(::CovMatrix, data::CovMatrixData) = data.n > 1
_combine(::CovMatrix, x::CovMatrixData, y::CovMatrixData) = _combine(x, y)
_extract(::CovMatrix{T,true}, data::CovMatrixData) where {T} = data.c ./ (data.n - 1)
_extract(::CovMatrix{T,false}, data::CovMatrixData) where {T} = data.c ./ data.n
Base.show(io::IO, ::CovMatrix{T}) where {T} = print(io, "CovMatrix{$T,?x?}")

function Statistics.cov(
    x::Node{<:AbstractVector{T}}; corrected::Bool=true
) where {T<:Number}
    _is_constant(x) && throw(ArgumentError("Cannot compute covariance of constant $x"))
    Out = output_type(/, T, Int)
    return obtain_node((x,), CovMatrix{Out,corrected}())
end

struct WindowCovMatrix{T,Corrected,EmitEarly} <:
       UnaryWindowOp{Matrix{T},CovMatrixData{T},EmitEarly}
    window::Int64
end
_should_tick(::WindowCovMatrix, data::CovMatrixData) = data.n > 1
_combine(::WindowCovMatrix, x::CovMatrixData, y::CovMatrixData) = _combine(x, y)
_extract(::WindowCovMatrix{T,true}, data::CovMatrixData) where {T} = data.c ./ (data.n - 1)
_extract(::WindowCovMatrix{T,false}, data::CovMatrixData) where {T} = data.c ./ data.n
function Base.show(io::IO, op::WindowCovMatrix{T}) where {T}
    return print(io, "WindowCovMatrix{$T,?x?}($(_window(op)))")
end
function Statistics.cov(
    x::Node{<:AbstractVector{T}}, window::Int; emit_early::Bool=false, corrected::Bool=true
) where {T<:Number}
    _is_constant(x) && throw(ArgumentError("Cannot compute variance of constant $x"))
    window >= 2 || throw(ArgumentError("Got window=$window, but should be at least 2"))
    Out = output_type(/, T, Int)
    return obtain_node((x,), WindowCovMatrix{Out,corrected,emit_early}(window))
end

# Correlation, cumulative over time.

"""
    cor(x, y[, alignment]; corrected::Bool=true) -> Node


Create a node which ticks with values of the running correlation of `x` and `y`.

The specified `alignment` controls the behaviour when `x` and `y` tick at different times,
as per the documentation in [Alignment](@ref). When not specified, it defaults to
[`UNION`](@ref).

This is equivalent to a sample correlation over the `n` values of `(x, y)` pairs observed at
and before a given time.
"""
function Statistics.cor(x, y, alignment::Alignment)
    # Do alignment first so that calls to cov & std so that we only do aligning work once.
    # Calls to cov & std should then be (relatively) trivial.
    x, y = coalign(x, y, alignment)
    return cov(x, y) / (std(x) * std(y))
end
Statistics.cor(x::Node, y::Node) = cor(x, y, DEFAULT_ALIGNMENT)
Statistics.cor(x::Node, y) = cov(x, y, DEFAULT_ALIGNMENT)
Statistics.cor(x, y::Node) = cov(x, y, DEFAULT_ALIGNMENT)

# Correlation over fixed window.

"""
    cor(x, y, window::Int[, alignment]; emit_early=false) -> Node

Create a node of the rolling covariance of `x` and `y` over the last `window` knots.

The specified `alignment` controls the behaviour when `x` and `y` tick at different times,
as per the documentation in [Alignment](@ref). When not specified, it defaults to
[`UNION`](@ref).

If `emit_early` is false, then the node returned will only start ticking once the window is
full. Otherwise, it will tick immediately with a partially-filled window.

This is equivalent to a sample correlation over the `n` values of `(x, y)` pairs observed at
and before a given time, with `n` capped at `window`.
"""
function Statistics.cor(x, y, window::Int, alignment::Alignment; emit_early::Bool=false)
    x, y = coalign(x, y, alignment)
    return cov(x, y, window; emit_early) /
           (std(x, window; emit_early) * std(y, window; emit_early))
end
function Statistics.cor(x::Node, y::Node, window::Int; emit_early::Bool=false)
    return cor(x, y, window, DEFAULT_ALIGNMENT; emit_early)
end
function Statistics.cor(x::Node, y, window::Int; emit_early::Bool=false)
    return cor(x, y, window, DEFAULT_ALIGNMENT; emit_early)
end
function Statistics.cor(x, y::Node, window::Int; emit_early::Bool=false)
    return cor(x, y, window, DEFAULT_ALIGNMENT; emit_early)
end

# TODO for time windows, it is safe to dispatch on the same functions with a TimePeriod
#   In the future, if we want to support more general types of time, we could introduce a
#   TimeDelta wrapper, that could server to distinguish between an Int64 "time" and an Int64
#   "number of knots".

struct EmaData{T}
    weighted_sum::T
    weighted_count::Float64
end

_wrap(::Type{EmaData{T}}, x) where {T} = EmaData{T}(x, 1.0)
struct Ema{T} <: UnaryInceptionOp{T,EmaData{T}}
    α::Float64
    function Ema{T}(α::Float64) where {T}
        0 < α < 1 || throw(ArgumentError("α = $α is outside of the valid range."))
        return new{T}(α)
    end
end
_unfiltered(::Ema) = true
function _update(op::Ema{T}, a::EmaData{T}, x) where {T}
    return EmaData(x + (1 - op.α) * a.weighted_sum, 1 + (1 - op.α) * a.weighted_count)
end
_extract(::Ema, data::EmaData) = data.weighted_sum / data.weighted_count
Base.show(io::IO, ::Ema{T}) where {T} = print(io, "Ema{$T}")

"""
    ema(x::Node, α::AbstractFloat) -> Node
    ema(x::Node, w_eff::Integer) -> Node

Create a node which computes the exponential moving average of `x`.

The decay is specified either by `α`, which should satisfy `0 < α < 1`, or by `w_eff`, which
should be an integer greater than 1. If the latter is specified, then we compute
`α = 2 / (w_eff + 1)`.

For internal state ``s_t``, with ``s_0 = 0``, and resulting EMA series ``m_t``, this has the
form:

```math
\\begin{aligned}
s_t &= s_{t-1} + (1 - \\alpha) x_t \\\\
m_t &= \\frac{\\alpha s_t}{1 - (1 - \\alpha)^t}.
\\end{aligned}
```

For further information, see the notational conventions and discussion on
(Wikipedia)[https://en.wikipedia.org/wiki/Moving_average#Exponential_moving_average]. Note
that this function implements the variant including the correction for the initial
convergence problem.
"""
function ema(x::Node, α::AbstractFloat)
    T = output_type(*, value_type(x), Float64)
    return obtain_node((x,), Ema{T}(α))
end
function ema(x::Node, w_eff::Integer)
    w_eff > 1 || throw(ArgumentError("w_eff = $w_eff is out of range"))
    return ema(x, 2 / (w_eff + 1))
end
