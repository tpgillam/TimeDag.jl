struct Negate{T} <: UnaryNodeOp{T} end
operator(::Negate, x) = -x

struct Add{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Add, x, y) = x + y

struct Subtract{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Subtract, x, y) = x - y


# API.

function negate(node::Node)
    if _is_constant(node)
        return constant(-node.op.value)
    end

    T = value_type(node)
    return obtain_node((node,), Negate{T}())
end

function add(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    if _is_constant(x) && _is_constant(y)
        # TODO refactor constant propagation into obtain_node
        # Constant propagation.
        return constant(x.op.value + y.op.value)
    end
    # Figure out the promotion of types from combining left & right.
    T = promote_type(value_type(x), value_type(y))
    return obtain_node((x, y), Add{T, A}())
end

function subtract(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    if _is_constant(x) && _is_constant(y)
        # TODO refactor constant propagation into obtain_node
        # Constant propagation.
        return constant(x.op.value - y.op.value)
    end

    # Figure out the promotion of types from combining left & right.
    T = promote_type(value_type(x), value_type(y))
    return obtain_node((x, y), Subtract{T, A}())
end

# Shorthand

Base.:-(node::Node) = negate(node)

Base.:+(x::Node, y::Node) = add(x, y)
Base.:+(x::Node, y) = add(x, y)
Base.:+(x, y::Node) = add(x, y)

Base.:-(x::Node, y::Node) = subtract(x, y)
Base.:-(x::Node, y) = subtract(x, y)
Base.:-(x, y::Node) = subtract(x, y)
