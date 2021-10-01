# Unary operators
const _UNARY_OP_TO_NODE_OP = Dict(
    :- => :Negate,
    :exp => :Exp,
    :log => :Log,
    :log10 => :Log10,
    :log2 => :Log2,
    :sqrt => :Sqrt,
    :cbrt => :Cbrt,
    # TODO This should probably live in e.g. logical.jl, but to avoid copy-pasta
    #   rewrite this code generation as a macro?
    :! => :Not,
)

# Generate the node op structures, and define basic traits.
for op in (:-, :exp, :log, :log10, :log2, :sqrt, :cbrt, :!)
    node_op = _UNARY_OP_TO_NODE_OP[op]
    @eval begin
        struct $node_op{T} <: UnaryNodeOp{T} end

        create_operator_evaluation_state(::Tuple{Node}, ::$node_op) = _EMPTY_NODE_STATE

        always_ticks(::$node_op) = true
        stateless(::$node_op) = true
        time_agnostic(::$node_op) = true

        operator!(::$node_op, x) = $op(x)
    end
end

# Generate code for all operators without special cases; the others are handled below.
for op in (:exp, :log, :log10, :log2, :sqrt, :cbrt)
    node_op = _UNARY_OP_TO_NODE_OP[op]
    @eval Base.$op(x::Node) = obtain_node((x,), $node_op{output_type($op, value_type(x))}())
end

function Base.:-(x::Node)
    if isa(x.op, Negate)
        # Optimisation: negating a negate node should yield the parent.
        return only(parents(x))
    end
    return obtain_node((x,), Negate{output_type(-, value_type(x))}())
end

function Base.:!(x::Node)
    if isa(x.op, Not)
        # Optimisation: notting a not node should yield the parent.
        return only(parents(x))
    end
    return obtain_node((x,), Not{output_type(!, value_type(x))}())
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
