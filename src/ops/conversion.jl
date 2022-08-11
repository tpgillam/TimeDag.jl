"""
    convert_value(T, x::Node[; upcast=false]) -> Node

Convert the values of node `x` to type `T`.

The value type of the resulting node is guaranteed to be `T` if and only if `upcast=true`.
See further discussion in the note.

!!! note
    By default, `convert_value` has similar semantics to `Base.convert`, which means that
    the [`value_type`](@ref) of the returned node might be a subtype of `T`.

    A concrete example:
    ```jldoctest
    julia> x = convert_value(Any, constant("hello"));

    julia> value_type(x)
    String
    ```
    Note that the same thing would happen if calling `convert(Any, "hello")`.

    However, if we set `upcast=true`:
    ```jldoctest
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

    # It is possible that T_ <: Out. The `upcast` argument determines whether we should
    # force use of `Out` rather than the subtype `T_`.
    T_Out = upcast ? Out : T_

    # If the conversion would be a no-op, then do not create a new node.
    T_Out == In && return x

    return apply(value -> convert(Out, value), x; out_type=T_Out)
end
