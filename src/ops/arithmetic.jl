# Unary operators
struct UnaryArithmeticOp{T, Op} <: StatelessUnaryNodeOp{T, true} end
operator(::UnaryArithmeticOp{T, Op}, x) where {T, Op} = Op(x)

for (alias, op) in [(:Negate, :-), (:Exp, :exp), (:Log, :log)]
    @eval begin
        const $alias{T} = UnaryArithmeticOp{T, $op}
        Base.$op(x::Node) = obtain_node((x,), $alias{output_type($op, value_type(x))}())
    end
end

# Binary operators
struct BinaryArithmeticOp{T, A, Op} <: BinaryAlignedNodeOp{T, A} end
operator(::BinaryArithmeticOp{T, A, Op}, x, y) where {T, A, Op} = Op(x, y)

for (long, short) in [(:add, :+), (:subtract, :-), (:multiply, :*), (:divide, :/)]
    alias_sym = Symbol(titlecase(string(long)))
    @eval begin
        const $alias_sym{T, A} = BinaryArithmeticOp{T, A, $short}

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
