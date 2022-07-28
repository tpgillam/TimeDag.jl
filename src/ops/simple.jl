# Arithmetic

@simple_unary(Base.abs)
@simple_unary(Base.exp)
@simple_unary(Base.log)
@simple_unary(Base.log10)
@simple_unary(Base.log2)
@simple_unary(Base.sqrt)
@simple_unary(Base.cbrt)
@simple_unary(Base.sign)
@simple_unary(Base.tan)
@simple_unary(Base.sin)
@simple_unary(Base.cos)
@simple_unary(Base.atan)
@simple_unary(Base.asin)
@simple_unary(Base.acos)
@simple_unary(Base.tanh)
@simple_unary(Base.sinh)
@simple_unary(Base.cosh)
@simple_unary(Base.atanh)
@simple_unary(Base.asinh)
@simple_unary(Base.acosh)
@simple_unary_self_inverse(Base.:-)
@simple_unary_self_inverse(Base.inv)

@simple_binary(Base.:+)
@simple_binary(Base.:-)
@simple_binary(Base.:*)
@simple_binary(Base.:/)
@simple_binary(Base.:^)
@simple_binary(Base.min)
@simple_binary(Base.max)

# Logical

@simple_unary_self_inverse(Base.:!)

@simple_binary(Base.:>)
@simple_binary(Base.:<)
@simple_binary(Base.:>=)
@simple_binary(Base.:<=)

# Linear algebra

@simple_binary(LinearAlgebra.dot)
