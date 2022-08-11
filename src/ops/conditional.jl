struct Filter{f,T} <: UnaryNodeOp{T} end

stateless_operator(::Filter) = true
time_agnostic(::Filter) = true
operator!(::Filter{f,T}, x) where {f,T} = f(x) ? Maybe(x) : Maybe{T}()

"""
    filter(f::Function, x::Node) -> Node

Obtain a node that removes knots for which `f(value)` is false.

The [`value_type`](@ref) of the returned node is the same as that for the input `x`.
"""
function Base.filter(f::Function, x::Node)
    _is_empty(x) && return x
    T = value_type(x)
    _is_constant(x) && return f(value(x)) ? x : empty_node(T)
    return obtain_node((x,), Filter{f,T}())
end

struct SkipMissing{T} <: UnaryNodeOp{T} end

stateless_operator(::SkipMissing) = true
time_agnostic(::SkipMissing) = true

function operator!(::SkipMissing{T}, x::Union{Missing,T}) where {T}
    return ismissing(x) ? Maybe{T}() : Maybe(x)
end

"""
    skipmissing(x::Node{T}) -> Node{nonmissingtype(T)}

Obtain a node which ticks with the values of `x`, so long as that value is not `missing`.

The [`value_type`](@ref) of the node that is returned will always be the `nonmissingtype` of
the `value_type` of `x`.

In the case that `x` cannot tick with `missing` (based on its `value_type`), we just return
`x`.
"""
function Base.skipmissing(x::Node)
    if !(Missing <: value_type(x))
        # There are provably no missing values in the input, so return the same node.
        return x
    end
    T = nonmissingtype(value_type(x))
    _is_constant(x) && return ismissing(value(x)) ? empty_node(T) : constant(T, value(x))
    _is_empty(x) && return empty_node(T)
    return obtain_node((x,), SkipMissing{T}())
end
