# Unary operators
for (node_op, op) in [
    (:Negate, :-),
    (:Exp, :exp),
    (:Log, :log),
    (:Log10, :log10),
    (:Log2, :log2),
    (:Sqrt, :sqrt),
    (:Cbrt, :cbrt),
    # TODO This should probably live in e.g. logical.jl, but to avoid copy-pasta
    #   rewrite this code generation as a macro?
    (:Not, :!),
]
    @eval begin
        struct $node_op{T} <: UnaryNodeOp{T} end

        create_operator_evaluation_state(::Tuple{Node}, ::$node_op) = _EMPTY_NODE_STATE

        always_ticks(::$node_op) = true
        stateless(::$node_op) = true
        time_agnostic(::$node_op) = true

        operator!(::$node_op, x) = $op(x)

        Base.$op(x::Node) = obtain_node((x,), $node_op{output_type($op, value_type(x))}())
    end
end

# Binary operators
for (node_op, op) in [
    (:Add, :+),
    (:Subtract, :-),
    (:Multiply, :*),
    (:Divide, :/),
    (:Power, :^),
    # TODO These should probably live in e.g. logical.jl, but to avoid copy-pasta
    #   rewrite this code generation as a macro?
    (:Greater, :>),
    (:Less, :<),
    (:GreaterEqual, :>=),
    (:LessEqual, :<=),
]
    @eval begin
        struct $node_op{T,A} <: BinaryAlignedNodeOp{T,A} end

        create_operator_evaluation_state(::Tuple{Node,Node}, ::$node_op) = _EMPTY_NODE_STATE

        always_ticks(::$node_op) = true
        stateless_operator(::$node_op) = true
        time_agnostic(::$node_op) = true

        operator!(::$node_op, x, y) = $op(x, y)

        function Base.$op(x, y, ::Type{A}) where {A<:Alignment}
            x = _ensure_node(x)
            y = _ensure_node(y)
            T = output_type($op, value_type(x), value_type(y))
            return obtain_node((x, y), $node_op{T,A}())
        end

        Base.$op(x::Node, y::Node) = $op(x, y, DEFAULT_ALIGNMENT)
        Base.$op(x::Node, y) = $op(x, y, DEFAULT_ALIGNMENT)
        Base.$op(x, y::Node) = $op(x, y, DEFAULT_ALIGNMENT)
    end
end
