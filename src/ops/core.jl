"""
    SimpleUnary{f,T}

Represents a stateless, time-independent unary operator that will always emit a value.
"""
struct SimpleUnary{f,T} <: UnaryNodeOp{T} end

always_ticks(::SimpleUnary) = true
stateless(::SimpleUnary) = true
time_agnostic(::SimpleUnary) = true
operator!(::SimpleUnary{f}, x) where {f} = f(x)

"""
    SimpleBinary{f,T,A}

Represents a stateless, time-independent binary operator that will always emit a value.
"""
struct SimpleBinary{f,T,A} <: BinaryAlignedNodeOp{T,A} end

always_ticks(::SimpleBinary) = true
stateless_operator(::SimpleBinary) = true
time_agnostic(::SimpleBinary) = true
operator!(::SimpleBinary{f}, x, y) where {f} = f(x, y)

"""
    apply(f::Function, x; out_type=nothing)
    apply(f::Function, x, y[, alignment=DEFAULT_ALIGNMENT]; out_type=nothing)

Obtain a node with values constructed by applying the pure function `f` to the input values.

With more than one argument an alignment can optionally be specified.

Internally this will infer the output type of `f` applied to the arguments, and will also
ensure that subgraph elimination occurs when possible.

If `out_type` is not specified, we attempt to infer the value type of the resulting node
automatically, using [`output_type`](@ref). Alternatively, if `out_type` is given as
anything other than `nothing`, it will be used instead.
"""
function apply(f::Function, x; out_type::Union{Nothing,Type}=nothing)
    x = _ensure_node(x)
    T = isnothing(out_type) ? output_type(f, value_type(x)) : out_type
    return obtain_node((x,), SimpleUnary{f,T}())
end

function apply(
    f::Function, x, y, ::A; out_type::Union{Nothing,Type}=nothing
) where {A<:Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    T = isnothing(out_type) ? output_type(f, value_type(x), value_type(y)) : out_type
    return obtain_node((x, y), SimpleBinary{f,T,A}())
end

function apply(f::Function, x::Node, y::Node; kwargs...)
    return apply(f, x, y, DEFAULT_ALIGNMENT; kwargs...)
end
apply(f::Function, x::Node, y; kwargs...) = apply(f, x, y, DEFAULT_ALIGNMENT; kwargs...)
apply(f::Function, x, y::Node; kwargs...) = apply(f, x, y, DEFAULT_ALIGNMENT; kwargs...)

"""
    BCast(f::Function)

Represent a function which should be broadcasted when called.

That is, `BCast{f}(x, y...)` is identical to `f.(x, y...)`.
"""
struct BCast{f} <: Function
    BCast(f::Function) = new{f}()
end
@inline (::BCast{f})(args...; kwargs...) where {f} = f.(args...; kwargs...)

"""
    Wrapped{f}

Represent a function that, when called, will expect its arguments to be nodes and try to
convert them as such.
"""
struct Wrapped{f} end
@inline (::Wrapped{f})(args...; kwargs...) where {f} = apply(f, args...; kwargs...)

# TODO Would we like an identity map? Not important right now, but could be in the future
#   if we allow stateful things?

"""
    wrap(f::Function)

Return a callable object that acts on nodes, and returns a node.

It is assumed that `f` is stateless and time-independent. We also assume that we will
always emit a knot when the alignment semantics say we should — thus `f` must always return
a valid output value.

If the object is called with more than one node, alignment will be performed. In this case,
the final argument can be an `Alignment` instance, otherwise `DEFAULT_ALIGNMENT` will be
used.

Internally this will call `TimeDag.apply(f, args...)`; see there for further details.
"""
wrap(f::Function) = Wrapped{f}()

"""
    wrapb(f::Function)

`wrapb` is like [`wrap`](@ref), however `f` will be broadcasted over all input values.
"""
wrapb(f::Function) = Wrapped{BCast(f)}()

"""
    @simple_unary(f)

Define a method `f(::Node)` that will obtain the correct instance of `SimpleUnary{f}`.

This will internally infer the output value, and perform subgraph elimination.
"""
macro simple_unary(f, self_inverse::Bool=false)
    f = esc(f)
    return quote
        $f(x::Node) = apply($f, x)
    end
end

"""
    @simple_unary_self_inverse(f)

Define a method `f(::Node)` that will obtain the correct instance of `SimpleUnary{f}`.

This must ONLY be used if `f(f(x)) == x` for all nodes `x`.

This will internally infer the output value, and perform subgraph elimination.
"""
macro simple_unary_self_inverse(f)
    f = esc(f)
    return quote
        function $f(x::Node)
            # Optimisation: self-inverse
            isa(x.op, SimpleUnary{$f}) && return only(parents(x))
            return apply($f, x)
        end
    end
end

"""
    @simple_binary(f)

Define methods `f(x, y)` that will obtain the correct instance of `SimpleBinary{f}`.

These will internally infer the output value, and perform subgraph elimination.
"""
macro simple_binary(f)
    f = esc(f)
    return quote
        $f(x, y, alignment::Alignment) = apply($f, x, y, alignment)
        $f(x::Node, y::Node) = $f(x, y, DEFAULT_ALIGNMENT)
        $f(x::Node, y) = $f(x, y, DEFAULT_ALIGNMENT)
        $f(x, y::Node) = $f(x, y, DEFAULT_ALIGNMENT)
    end
end
