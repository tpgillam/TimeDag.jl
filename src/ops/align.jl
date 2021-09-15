struct Left{T, A} <: BinaryAlignedNodeOp{T, A} end

create_operator_evaluation_state(::Tuple{Node, Node}, ::Left) = _EMPTY_NODE_STATE

always_ticks(::Left) = true
stateless_operator(::Left) = true
time_agnostic(::Left) = true

function operator!(::Left, out::Ref, x, y)
    @inbounds out[] = x
    return true
end

struct Right{T, A} <: BinaryAlignedNodeOp{T, A} end

create_operator_evaluation_state(::Tuple{Node, Node}, ::Right) = _EMPTY_NODE_STATE

always_ticks(::Right) = true
stateless_operator(::Right) = true
time_agnostic(::Right) = true

function operator!(::Right, out::Ref, x, y)
    @inbounds out[] = y
    return true
end

# API

# TODO We should add the concept of alignment_base, i.e. an ancestor that provably has the
#   same alignment as a particular node. This can allow for extra pruning of the graph.

function left(x, y, ::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    return obtain_node((x, y), Left{value_type(x), A}())
end

function right(x, y, ::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    x = _ensure_node(x)
    y = _ensure_node(y)
    return obtain_node((x, y), Right{value_type(y), A}())
end

"""
    align(x, y)

Form a node that ticks with the values of x whenever y ticks.
"""
align(x, y) = right(y, x, LeftAlignment)
