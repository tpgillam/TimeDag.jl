"""
    output_type(f, arg_types...)

Return the output type of the specified function. Tries to be fast where possible.

!!! warning
    This uses `Base.promote_op`, which is noted to be fragile. The problem is that whilst
    one might hope that `typeof(f(map(oneunit, arg_types)...))` could be used, in practice
    there are a lot of types which do not define `oneunit`.

    Ultimately this represents a tension between the desire of `TimeDag` to know the _type_
    of the output of a node without yet knowing the concrete values of the input type.
"""
output_type(f, arg_types...) = Base.promote_op(f, arg_types...)
