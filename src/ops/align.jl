_left(x, _) = x
_right(_, y) = y

# TODO We should add the concept of alignment_base, i.e. an ancestor that provably has the
#   same alignment as a particular node. This can allow for extra pruning of the graph.

"""
    left(x, y[, alignment::Alignment; initial_values=nothing])

Construct a node that ticks according to `alignment` with the latest value of `x`.

It is "left", in the sense of picking the left-hand of the two arguments `x` and `y`.
"""
function left(x, y, alignment::Alignment=DEFAULT_ALIGNMENT; initial_values=nothing)
    return apply(_left, x, y, alignment; initial_values)
end

"""
    right(x, y[, alignment::Alignment; initial_values=nothing])

Construct a node that ticks according to `alignment` with the latest value of `y`.

It is "right", in the sense of picking the right-hand of the two arguments `x` and `y`.
"""
function right(x, y, alignment::Alignment=DEFAULT_ALIGNMENT; initial_values=nothing)
    return apply(_right, x, y, alignment; initial_values)
end

"""
    align(x, y)

Form a node that ticks with the values of `x` whenever `y` ticks.
"""
align(x, y) = right(y, x, LEFT)

# TODO support initial_values in coalign.
"""
    coalign(node_1, [node_2...; alignment::Alignment]) -> Node...

Given at least one node(s) `x`, or values that are convertible to nodes, align all of them.

We guarantee that all nodes that are returned will have the same alignment. The values of
each node will correspond to the values of the input nodes.

The choice of alignment is controlled by `alignment`, which defaults to [`UNION`](@ref).
"""
function coalign(x, x_rest...; alignment::Alignment=DEFAULT_ALIGNMENT)
    x = map(_ensure_node, [x, x_rest...])

    # Deal with simple case where we only have one input. There is no aligning to do.
    length(x) == 1 && return only(x)

    # Find a well-defined ordering of the inputs -- this is an optimisation designed to
    # avoid creating equivalent nodes if `coalign` is called multiple times.
    # As such we use objectid. Strictly this is a hash, and so there could be clashes. We
    # accept this, since if such a clash were to occur it would result only in sub-optimal
    # performance, and most likely in a very minor way.
    index = if isa(alignment, LeftAlignment)
        # For left alignment we must leave the first node in place.
        [1; 1 .+ sortperm(@view(x[2:end]); by=objectid)]
    else
        sortperm(x; by=objectid)
    end
    x, x_rest... = x[index]

    # Construct one node with the correct alignment. This will also have the correct values
    # for the first node to return.
    for node in x_rest
        x = left(x, node, alignment)
    end

    # For all of the remaining nodes, align them.
    new_nodes = (x, (align(node, x) for node in x_rest)...)

    # Convert nodes back to original order.
    return new_nodes[invperm(index)]
end
