"""
    duplicate(x)

Return an object that is equal to x, but fully independent of it.

Note that for any parts of x that are considered to be immutable (e.g. `Block`s), this can
return the identical object.

Conceptually this is otherwise very similar to `deepcopy(x)`.
"""
function duplicate(x)
    isbitstype(typeof(x)) && return x
    return duplicate_internal(x, IdDict())::typeof(x)
end

"""
Internal implementation of duplicate.

By default delegates to deepcopy, but this can be avoided where it is known to be
unnecessary.
"""
duplicate_internal(x, stackdict::IdDict) = Base.deepcopy_internal(x, stackdict)
