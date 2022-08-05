struct Rand{T} <: UnaryNodeOp{T}
    rng::AbstractRNG
    args::Tuple  # A tuple of arguments that will be passed to `Base.rand` when evaluating.
end

Base.hash(x::Rand{T}, h::UInt64) where {T} = foldr(hash, (:Rand, T, x.rng, x.args); init=h)
Base.:(==)(x::Rand{T}, y::Rand{T}) where {T} = x.rng == y.rng && x.args == y.args

mutable struct RandState{RNG<:AbstractRNG} <: NodeEvaluationState
    rng::RNG
end

operator!(op::Rand, state::RandState) = rand(state.rng, op.args...)

always_ticks(::Rand) = true
time_agnostic(::Rand) = true
value_agnostic(::Rand) = true
# Note that we should never mutate the random state on the node op itself.
create_operator_evaluation_state(::Tuple{Node}, op::Rand) = RandState(copy(op.rng))

# See docstring below — Xoshiro only exists (and is the default) in Julia 1.7 and later.
_make_rng() = VERSION < v"1.7.0" ? MersenneTwister() : Xoshiro()

# This is the default data type used in `Random.jl`.
# We will use this explicitly whenever `S` is not provided.
const _RAND_T = Float64

"""
    rand([rng=...,] alignment::Node[, S, dims...])

Generate random numbers aligned to `alignment`, with the given `rng` if provided.

Semantics are otherwise very similar to the usual `Base.rand`:
* If specified, `S` will be one of
    * the element type
    * a set of values from which to select

    `S` will default to `Float64` otherwise.
* If specified, `dims` should be a tuple or vararg of integers representing the dimensions
    of an array.

!!! note
    The values of the knots from `alignment` will be ignored.

!!! note
    The default value of `rng` on Julia 1.6 is `MersenneTwister()`. On Julia 1.7 and later
    it is `Xoshiro()`. This matches the default random number generator used in the
    language.

!!! tip
    If provided, `rng` will be copied before it is used. This is to ensure reproducability
    when evaluating a node multiple times.
"""
Base.rand(x::Node, S, d::Dims) = rand(x, S, d...)
Base.rand(rng::AbstractRNG, x::Node, S, d::Dims) = rand(rng, x, S, d...)
# (comment applies to the above - necessary so docstring gets assigned to the function)
# Anything involving `Dims` as a non-empty tuple is going to get remapped to a version with
# splatted arguments. This ensures better subgraph elimination.

# The case of an _empty_ Dims tuple has to be handled separately, otherwise we end up
# recursing.  We don't want to splat an empty tuple, since that would change behaviour (by
# giving a scalar rather than a dimension-zero array).
Base.rand(x::Node, S, d::Tuple{}) = _rand(x, S, d)
Base.rand(rng::AbstractRNG, x::Node, S, d::Tuple{}) = _rand(copy(rng), x, S, d)

# The following are defined to avoid ambiguities. In the case that `S` is not provided, we
# replace it with the default random data type — this ensures better subgraph elimination.
Base.rand(x::Node, d::Integer...) = _rand(x, _RAND_T, d...)
Base.rand(x::Node, S, d::Integer...) = _rand(x, S, d...)
Base.rand(rng::AbstractRNG, x::Node, d::Integer...) = _rand(copy(rng), x, _RAND_T, d...)
Base.rand(rng::AbstractRNG, x::Node, S, d::Integer...) = _rand(copy(rng), x, S, d...)

"""
    _rand(alignment::Node, args...)
    _rand(rng::AbstractRNG, alignment::Node, args...)

Internal generation of a `Rand` node.

!!! warning
    If providing `rng` explicitly, a reference to it *must not* be kept by the caller.
    This is because external mutation of `rng` will break repeatability of node evaluation.
"""
_rand(alignment::Node, args...) = _rand(_make_rng(), alignment, args...)
function _rand(rng::AbstractRNG, alignment::Node, args...)
    # Note: using `Core.typeof` rather than `typeof` here, since one of the arguments could
    # itself be a type. In this case, e.g. `typeof(Int32) == DataType`, whereas
    # `Core.Typeof(Int32) == Type{Int32}`, which is more specific, and hence more useful
    # here for value type inference.
    T = output_type(rand, typeof(rng), map(Core.Typeof, args)...)
    return obtain_node((alignment,), Rand{T}(rng, args))
end
