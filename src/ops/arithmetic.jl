# Unary operators

struct Negate{T} <: UnaryNodeOp{T} end
operator(::Negate, x) = -x
Base.:-(node::Node) = obtain_node((node,), Negate{value_type(node)}())

struct Exp{T} <: UnaryNodeOp{T} end
operator(::Exp, x) = exp(x)
# TODO Nicer way to encode the type promotion?
Base.exp(node::Node) = obtain_node((node,), Exp{typeof(log(one(value_type(node))))}())

struct Log{T} <: UnaryNodeOp{T} end
operator(::Log, x) = log(x)
# TODO Nicer way to encode the type promotion?
Base.log(node::Node) = obtain_node((node,), Log{typeof(log(one(value_type(node))))}())

# Binary operators

struct Add{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Add, x, y) = x + y

struct Subtract{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Subtract, x, y) = x - y

function add(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    # Figure out the promotion of types from combining left & right.
    T = promote_type(value_type(x), value_type(y))
    return obtain_node((x, y), Add{T, A}())
end

function subtract(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    # Figure out the promotion of types from combining left & right.
    T = promote_type(value_type(x), value_type(y))
    return obtain_node((x, y), Subtract{T, A}())
end

# Shorthand

Base.:+(x::Node, y::Node) = add(x, y)
Base.:+(x::Node, y) = add(x, y)
Base.:+(x, y::Node) = add(x, y)

Base.:-(x::Node, y::Node) = subtract(x, y)
Base.:-(x::Node, y) = subtract(x, y)
Base.:-(x, y::Node) = subtract(x, y)
