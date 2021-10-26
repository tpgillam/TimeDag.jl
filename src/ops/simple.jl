# Arithmetic

@unary_define(Base.exp, Exp)
@unary_define(Base.log, Log)
@unary_define(Base.log10, Log10)
@unary_define(Base.log2, Log2)
@unary_define(Base.sqrt, Sqrt)
@unary_define(Base.cbrt, Cbrt)

@unary_define_without_op(Base.:-, Negate)
function Base.:-(x::Node)
    if isa(x.op, Negate)
        # Optimisation: negating a negate node should yield the parent.
        return only(parents(x))
    end
    return obtain_node((x,), Negate{output_type(-, value_type(x))}())
end

@unary_define_without_op(Base.inv, Inv)
function Base.inv(x::Node)
    if isa(x.op, Inv)
        # Optimisation: inverting a Inv node should yield the parent.
        return only(parents(x))
    end
    return obtain_node((x,), Inv{output_type(inv, value_type(x))}())
end

@binary_define(Base.:+, Add)
@binary_define(Base.:-, Subtract)
@binary_define(Base.:*, Multiply)
@binary_define(Base.:/, Divide)
@binary_define(Base.:^, Power)
@binary_define(Base.min, Min)
@binary_define(Base.max, Max)
function Base.min(x::Node, y::Node, z::Node, args...)
    return min(min(x, y), z, args...)
end
function Base.max(x::Node, y::Node, z::Node, args...)
    return max(max(x, y), z, args...)
end

# Logical

@unary_define_without_op(Base.:!, Not)
function Base.:!(x::Node)
    if isa(x.op, Not)
        # Optimisation: notting a not node should yield the parent.
        return only(parents(x))
    end
    return obtain_node((x,), Not{output_type(!, value_type(x))}())
end

@binary_define(Base.:>, Greater)
@binary_define(Base.:<, Less)
@binary_define(Base.:>=, GreaterEqual)
@binary_define(Base.:<=, LessEqual)
