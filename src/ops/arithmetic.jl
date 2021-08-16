struct Negate{T} <: UnaryNodeOp{T} end
operator(::Negate) = -

struct Add{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Add) = +

struct Subtract{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Subtract) = -

# API.

function negate(node::Node)
    if _is_constant(node)
        return constant(-node.op.value)
    end

    T = value_type(node)
    return obtain_node((node,), Negate{T}())
end

function add(node_l, node_r; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    node_l = _ensure_node(node_l)
    node_r = _ensure_node(node_r)
    if _is_constant(node_l) && _is_constant(node_r)
        # Constant propagation.
        return constant(node_l.op.value + node_r.op.value)
    end
    # Figure out the promotion of types from combining left & right.
    T = promote_type(value_type(node_l), value_type(node_r))
    return obtain_node((node_l, node_r), Add{T, alignment}())
end

function subtract(
    node_l,
    node_r;
    alignment::Type{A}=DEFAULT_ALIGNMENT,
) where {A <: Alignment}
    node_l = _ensure_node(node_l)
    node_r = _ensure_node(node_r)
    if _is_constant(node_l) && _is_constant(node_r)
        # Constant propagation.
        return constant(node_l.op.value - node_r.op.value)
    end

    # Figure out the promotion of types from combining left & right.
    T = promote_type(value_type(node_l), value_type(node_r))
    return obtain_node((node_l, node_r), Subtract{T, alignment}())
end

# Shorthand

Base.:-(node::Node) = negate(node)

Base.:+(node_l::Node, node_r::Node) = add(node_l, node_r)
Base.:+(node_l::Node, node_r) = add(node_l, node_r)
Base.:+(node_l, node_r::Node) = add(node_l, node_r)

Base.:-(node_l::Node, node_r::Node) = subtract(node_l, node_r)
Base.:-(node_l::Node, node_r) = subtract(node_l, node_r)
Base.:-(node_l, node_r::Node) = subtract(node_l, node_r)
