struct Left{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Left, x, y) = x

struct Right{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Right, x, y) = y

# API

# TODO We should add the concept of alignment_base, i.e. an ancestor that provably has the
#   same alignment as a particular node. This can allow for extra pruning of the graph.

function left(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    return obtain_node((x, y), Left{value_type(x), A}())
end

function right(x, y; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    return obtain_node((x, y), Right{value_type(y), A}())
end

"""
    align(x, y)

Form a node that ticks with the values of x whenever y ticks.
"""
align(x, y) = right(y, x; alignment=LeftAlignment)
