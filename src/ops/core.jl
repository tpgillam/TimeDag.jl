macro unary_define_without_op(op, node_op)
    op = esc(op)
    node_op = esc(node_op)
    return quote
        struct $node_op{T} <: UnaryNodeOp{T} end

        TimeDag.always_ticks(::$node_op) = true
        TimeDag.stateless(::$node_op) = true
        TimeDag.time_agnostic(::$node_op) = true

        TimeDag.operator!(::$node_op, x) = $op(x)
    end
end

macro unary_define(op, node_op)
    op = esc(op)
    node_op = esc(node_op)
    return quote
        @unary_define_without_op($op, $node_op)
        $op(x::Node) = obtain_node((x,), $node_op{output_type($op, value_type(x))}())
    end
end

macro binary_define(op, node_op)
    op = esc(op)
    node_op = esc(node_op)
    return quote
        struct $node_op{T,A} <: BinaryAlignedNodeOp{T,A} end

        TimeDag.always_ticks(::$node_op) = true
        TimeDag.stateless_operator(::$node_op) = true
        TimeDag.time_agnostic(::$node_op) = true

        TimeDag.operator!(::$node_op, x, y) = $op(x, y)

        function $op(x, y, ::Type{A}) where {A<:Alignment}
            x = _ensure_node(x)
            y = _ensure_node(y)
            T = output_type($op, value_type(x), value_type(y))
            return obtain_node((x, y), $node_op{T,A}())
        end

        $op(x::Node, y::Node) = $op(x, y, DEFAULT_ALIGNMENT)
        $op(x::Node, y) = $op(x, y, DEFAULT_ALIGNMENT)
        $op(x, y::Node) = $op(x, y, DEFAULT_ALIGNMENT)
    end
end
