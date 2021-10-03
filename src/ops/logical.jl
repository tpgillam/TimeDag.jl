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
