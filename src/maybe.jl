"""
    Maybe{T}()
    Maybe(value::T)

A structure which can hold a value of type `T`, or represent the absence of a value.

The API is optimised for speed over memory usage, by allowing a function that may otherwise
return `Union{T, Nothing}` to instead always return `Maybe{T}`, and hence be type-stable.
"""
struct Maybe{T}
    # TODO see the changes in this merge request:
    #   https://github.com/iamed2/ResultTypes.jl/commit/24e0aa779a29376ce3320cd8f106c5416aaff4c1
    # It may be possible to improve performance by using Union{Some{T},Nothing} instead of
    # this partial initialisation approach.
    valid::Bool
    value::T

    Maybe{T}() where {T} = new{T}(false)
    Maybe(value::T) where {T} = new{T}(true, value)
end

"""
    valid(x::Maybe) -> Bool

Return true iff `x` holds a value.
"""
valid(x::Maybe) = x.valid

"""
    value(x::Maybe{T}) -> T

Returns the value stored in `x`, or throws an `ArgumentError` if `!valid(x)`.

Note that, in a tight loop, it is preferable to use a combination of calls to `valid` and
`unsafe_value`, as it will generate more optimal code.
"""
value(x::Maybe) = valid(x) ? unsafe_value(x) : throw(ArgumentError("$x has no value."))

"""
    unsafe_value(x::Maybe{T}) -> T

Returns the value stored in `x`.

It is "unsafe" when `!valid(x)`, in that the return value of this function is undefined. If
`T` is a reference type, calling this function will result in an `UndefRefError` being
thrown.
"""
unsafe_value(x::Maybe) = x.value

function Base.show(io::IO, x::Maybe{T}) where {T}
    if valid(x)
        print(io, "Maybe{$T}($(x.value))")
    else
        print(io, "Maybe{$T}()")
    end
end
