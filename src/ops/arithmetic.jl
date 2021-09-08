# Unary operators
for (alias, op) in [
        (:Negate, :-),
        (:Exp, :exp), (:Log, :log), (:Log10, :log10), (:Log2, :log2),
        (:Sqrt, :sqrt), (:Cbrt, :cbrt)
    ]
    @eval begin
        struct $alias{T} <: StatelessUnaryNodeOp{T, true} end
        operator(::$alias{T}, x) where {T} = $op(x)
        Base.$op(x::Node) = obtain_node((x,), $alias{output_type($op, value_type(x))}())
    end
end

# Binary operators
for (long, short) in [
        (:add, :+), (:subtract, :-), (:multiply, :*), (:divide, :/), (:power, :^)
    ]
    alias_sym = Symbol(titlecase(string(long)))
    @eval begin
        struct $alias_sym{T, A} <: BinaryAlignedNodeOp{T, A} end
        operator(::$alias_sym{T, A}, x, y) where {T, A} = $short(x, y)

        function $long(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
            x = _ensure_node(x)
            y = _ensure_node(y)
            T = output_type($short, value_type(x), value_type(y))
            return obtain_node((x, y), $alias_sym{T, A}())
        end

        Base.$short(x::Node, y::Node) = $long(x, y)
        Base.$short(x::Node, y) = $long(x, y)
        Base.$short(x, y::Node) = $long(x, y)
    end
end
