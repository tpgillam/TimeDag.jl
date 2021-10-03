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

@binary_define(Base.:+, Add)
@binary_define(Base.:-, Subtract)
@binary_define(Base.:*, Multiply)
@binary_define(Base.:/, Divide)
@binary_define(Base.:^, Power)
