"""
    convert_value(T, x::Node[; upcast=false]) -> Node

Convert the node `x` to value type `T`, possibly generating a new value.

If and only if `upcast` is `true`, we will always upcast the result of the conversion to
`T` — the value type of the resulting node will always be `T` in this case.

!!! note
    By default, this has similar semantics to `Base.convert`, which means that the
    [`value_type`](@ref) of the returned node might be a subtype of `T`.

    A concrete example:
    ```julia
    julia> x = convert_value(Any, constant("hello"));
    julia> value_type(x)
    String
    ```
    Note that the same thing would happen if calling `convert(Any, "hello")`.

    However, if we set `upcast=true`:
    ```julia
    julia> x = convert_value(Any, constant("hello"); upcast=true);
    julia> value_type(x)
    Any
    ```
"""
function convert_value(::Type{Out}, x::Node{In}; upcast::Bool=false) where {Out,In}
    T_ = output_type(convert, Type{Out}, value_type(x))

    # It should be the case that T_ <: Out, although they may not be equal. For example, if
    # Out = Any, and value_type(x) == Int64, then we'll find that T_ == Int64.
    # But if Out = Float64, then we'll get T_ = Float64.
    T_ == Union{} && throw(ArgumentError("Cannot convert $In to type $Out"))

    # It is possible that T_ <: T. The `upcast` argument determines to which value we
    T_Out = upcast ? Out : T_

    # If the conversion would be a no-op, then do not create a new node.
    T_Out == In && return x

    return apply(value -> convert(Out, value), x; out_type=T_Out)
end
