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
    @simple_unary(f)

Define a method `f(::Node)` that will obtain the correct instance of `SimpleUnary{f}`.

This will internally infer the output value, and perform subgraph elimination.
"""
macro simple_unary(f, self_inverse::Bool=false)
    f = esc(f)
    return quote
        $f(x::Node) = obtain_node((x,), SimpleUnary{$f,output_type($f, value_type(x))}())
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
            return obtain_node((x,), SimpleUnary{$f,output_type($f, value_type(x))}())
        end
    end
end

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
    @simple_binary(f)

Define methods `f(x, y)` that will obtain the correct instance of `SimpleBinary{f}`.

These will internally infer the output value, and perform subgraph elimination.
"""
macro simple_binary(f)
    f = esc(f)
    return quote
        function $f(x, y, ::A) where {A<:Alignment}
            x = _ensure_node(x)
            y = _ensure_node(y)
            T = output_type($f, value_type(x), value_type(y))
            return obtain_node((x, y), SimpleBinary{$f,T,A}())
        end

        $f(x::Node, y::Node) = $f(x, y, DEFAULT_ALIGNMENT)
        $f(x::Node, y) = $f(x, y, DEFAULT_ALIGNMENT)
        $f(x, y::Node) = $f(x, y, DEFAULT_ALIGNMENT)
    end
end
