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
function Base.min(x::Node, y::Node, z::Node, args...)
    return min(min(x, y), z, args...)
end
function Base.max(x::Node, y::Node, z::Node, args...)
    return max(max(x, y), z, args...)
end

# Logical

@simple_unary_self_inverse(Base.:!)

@simple_binary(Base.:>)
@simple_binary(Base.:<)
@simple_binary(Base.:>=)
@simple_binary(Base.:<=)
