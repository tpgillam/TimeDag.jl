"""
    output_type(f, arg_types...)

Return the output type of the specified function. Tries to be fast where possible.
"""
function output_type(f, arg_types...)
    candidates = Base.return_types(f, arg_types)
    length(candidates) > 1 && throw(ArgumentError(
        "Got multiple return types for $(f)$(arg_types): $candidates"
    ))
    return only(candidates)
end

output_type(::typeof(-), x) = x
# TODO more efficient versions for common exp & log cases

output_type(::typeof(+), x, y) = promote_type(x, y)
output_type(::typeof(-), x, y) = promote_type(x, y)
output_type(::typeof(*), x, y) = promote_type(x, y)

output_type(::typeof(/), ::Type{T}, ::Type{T}) where {T<:AbstractFloat} = T
function output_type(::typeof(/), ::Type{X}, ::Type{Y}) where {X<:Real,Y<:Real}
    T = promote_type(X, Y)
    return output_type(/, T, T)
end
output_type(::typeof(/), ::Type{T}, ::Type{T}) where {T<:Integer} = Float64
