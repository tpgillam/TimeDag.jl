struct Left{T,A} <: BinaryAlignedNodeOp{T,A} end

always_ticks(::Left) = true
stateless_operator(::Left) = true
time_agnostic(::Left) = true

operator!(::Left, x, y) = x

struct Right{T,A} <: BinaryAlignedNodeOp{T,A} end

always_ticks(::Right) = true
stateless_operator(::Right) = true
time_agnostic(::Right) = true

operator!(::Right, x, y) = y

# API

# TODO We should add the concept of alignment_base, i.e. an ancestor that provably has the
#   same alignment as a particular node. This can allow for extra pruning of the graph.

"""
    left(x, y[, alignment::Alignment])

Construct a node that ticks according to `alignment` with the latest value of `x`.

It is "left", in the sense of picking the left-hand of the two arguments `x` and `y`.
"""
function left(x, y, ::A=DEFAULT_ALIGNMENT) where {A<:Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    return obtain_node((x, y), Left{value_type(x),A}())
end

"""
    right(x, y[, alignment::Alignment])

Construct a node that ticks according to `alignment` with the latest value of `y`.

It is "right", in the sense of picking the right-hand of the two arguments `x` and `y`.
"""
function right(x, y, ::A=DEFAULT_ALIGNMENT) where {A<:Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    return obtain_node((x, y), Right{value_type(y),A}())
end

"""
    align(x, y)

Form a node that ticks with the values of `x` whenever `y` ticks.
"""
align(x, y) = right(y, x, LEFT)
