# Unary operators

struct Negate{T} <: StatelessUnaryNodeOp{T, true} end
operator(::Negate, x) = -x
Base.:-(x::Node) = obtain_node((x,), Negate{value_type(x)}())

struct Exp{T} <: StatelessUnaryNodeOp{T, true} end
operator(::Exp, x) = exp(x)
# FIXME Use output_type
Base.exp(x::Node) = obtain_node((x,), Exp{typeof(exp(one(value_type(x))))}())

struct Log{T} <: StatelessUnaryNodeOp{T, true} end
operator(::Log, x) = log(x)
# FIXME Use output_type
Base.log(x::Node) = obtain_node((x,), Log{typeof(log(one(value_type(x))))}())

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
