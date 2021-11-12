# Arithmetic

@simple_unary(Base.exp)
@simple_unary(Base.log)
@simple_unary(Base.log10)
@simple_unary(Base.log2)
@simple_unary(Base.sqrt)
@simple_unary(Base.cbrt)
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
