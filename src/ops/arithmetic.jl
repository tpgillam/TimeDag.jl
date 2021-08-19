# Unary operators

struct Negate{T} <: StatelessUnaryNodeOp{T, true} end
operator(::Negate, x) = -x
Base.:-(x::Node) = obtain_node((x,), Negate{value_type(x)}())

struct Exp{T} <: StatelessUnaryNodeOp{T, true} end
operator(::Exp, x) = exp(x)
# TODO Nicer way to encode the type promotion?
Base.exp(x::Node) = obtain_node((x,), Exp{typeof(exp(one(value_type(x))))}())

struct Log{T} <: StatelessUnaryNodeOp{T, true} end
operator(::Log, x) = log(x)
# TODO Nicer way to encode the type promotion?
Base.log(x::Node) = obtain_node((x,), Log{typeof(log(one(value_type(x))))}())

# Binary operators

struct Add{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Add, x, y) = x + y
function add(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    T = output_type(+, value_type(x), value_type(y))
    return obtain_node((x, y), Add{T, A}())
end
Base.:+(x::Node, y::Node) = add(x, y)
Base.:+(x::Node, y) = add(x, y)
Base.:+(x, y::Node) = add(x, y)

struct Subtract{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Subtract, x, y) = x - y
function subtract(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    T = output_type(-, value_type(x), value_type(y))
    return obtain_node((x, y), Subtract{T, A}())
end
Base.:-(x::Node, y::Node) = subtract(x, y)
Base.:-(x::Node, y) = subtract(x, y)
Base.:-(x, y::Node) = subtract(x, y)

struct Divide{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Divide, x, y) = x / y
function divide(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    T = output_type(/, value_type(x), value_type(y))
    return obtain_node((x, y), Divide{T, A}())
end
Base.:/(x::Node, y::Node) = divide(x, y)
Base.:/(x::Node, y) = divide(x, y)
Base.:/(x, y::Node) = divide(x, y)
