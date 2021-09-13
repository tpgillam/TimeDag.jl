# Unary operators
for (alias, op) in [
        (:Negate, :-),
        (:Exp, :exp), (:Log, :log), (:Log10, :log10), (:Log2, :log2),
        (:Sqrt, :sqrt), (:Cbrt, :cbrt),
        # TODO This should probably live in e.g. logical.jl, but to avoid copy-pasta
        #   rewrite this code generation as a macro?
        (:Not, :!),
    ]
    @eval begin
        struct $alias{T} <: StatelessUnaryNodeOp{T, true} end
        operator(::$alias{T}, x) where {T} = $op(x)
        Base.$op(x::Node) = obtain_node((x,), $alias{output_type($op, value_type(x))}())
    end
end

# Binary operators
for (alias, op) in [
        (:Add, :+), (:Subtract, :-), (:Multiply, :*), (:Divide, :/), (:Power, :^),
        # TODO These should probably live in e.g. logical.jl, but to avoid copy-pasta
        #   rewrite this code generation as a macro?
        (:Greater, :>), (:Less, :<), (:GreaterEqual, :>=), (:LessEqual, :<=)
    ]
    @eval begin
        struct $alias{T, A} <: BinaryAlignedNodeOp{T, A} end
        operator(::$alias{T, A}, x, y) where {T, A} = $op(x, y)

        function Base.$op(x, y, ::Type{A}) where {A <: Alignment}
            x = _ensure_node(x)
            y = _ensure_node(y)
            T = output_type($op, value_type(x), value_type(y))
            return obtain_node((x, y), $alias{T, A}())
        end

        Base.$op(x::Node, y::Node) = $op(x, y, DEFAULT_ALIGNMENT)
        Base.$op(x::Node, y) = $op(x, y, DEFAULT_ALIGNMENT)
        Base.$op(x, y::Node) = $op(x, y, DEFAULT_ALIGNMENT)
    end
end
