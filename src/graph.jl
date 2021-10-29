"""
    _can_propagate_constant(::NodeOp) -> Bool

Return true for ops which can propagate constant values if all their parents are constant.
"""
_can_propagate_constant(::NodeOp) = false

"""
    _propagate_constant_value(op::NodeOp{T}, parents::NTuple{N, Node}) -> T

Given that all parents are constants, get the value of the constant node we should output.
This assumes that `_can_propagate_constant(op)` is true.
"""
function _propagate_constant_value end

"""
    obtain_node(parents::NTuple{N,Node}, op::NodeOp) -> Node

Get a node for the given `op` and `parents`. If an equivalent node already exists in the
global identity map, use that one, otherwise create a new node, add to the identity map, and
return it.

# Constant propagation
If all `parents` are constant nodes, and `op` has a well-defined operation on constant
inputs, we will immediately perform the computation and return a constant node wrapping the
computed value.
"""
function obtain_node(parents::NTuple{N,Node}, op::NodeOp) where {N}
    if !isempty(parents) && _can_propagate_constant(op) && all(_is_constant, parents)
        # Constant propagation, since all inputs are constants & the op supports it.
        # Note that `constant` does, itself, call through to `obtain_node`, so the node will
        # be correctly registered with the id_map.
        return constant(_propagate_constant_value(op, parents))
    end

    return obtain_node!(global_identity_map(), parents, op)
end

"""
    ancestors(graph::AbstractGraph{T}, sources::AbstractVector{T}) -> Vector{T}

Given a (directed) graph, with edges from child to parent, find all ancestor vertices of the
given `sources`.

The result will be ordered such that the parents of any given vertex will always come before
the vertex itself.
"""
function ancestors(graph::AbstractGraph{T}, sources::AbstractVector{T}) where {T}
    isempty(sources) && throw(ArgumentError("Need at least 1 source"))

    seen = Set{T}()

    stack = Vector(sources)

    # Get the search data for the current source.
    while !isempty(stack)
        vertex = popfirst!(stack)
        # Either continue if we've seen this vertex before, or add it to the seen nodes.
        if vertex in seen
            continue
        else
            push!(seen, vertex)
        end
        append!(stack, outneighbors(graph, vertex))
    end

    # This won't be the most efficient way of ordering the results, especially when we only
    # care about a small subgraph.
    order = topological_sort_by_dfs(graph)
    reverse!(order)
    return [v for v in order if v in seen]
end

struct NodeIterator
    nodes::Vector{Node}
end

struct NodeIteratorState
    stack::Vector{Node}
    seen::Set{Node}
    NodeIteratorState(ni::NodeIterator) = new(ni.nodes, Set())
end

Base.IteratorSize(::Type{NodeIterator}) = Base.SizeUnknown()
Base.eltype(::Type{NodeIterator}) = Node
Base.iterate(ni::NodeIterator) = iterate(ni, NodeIteratorState(ni))
function Base.iterate(::NodeIterator, state::NodeIteratorState)
    # Find a node on the stack that we haven't seen already.
    local node
    while true
        isempty(state.stack) && return nothing
        node = popfirst!(state.stack)
        in(node, state.seen) || break
    end

    # We now know that this is a new node, so process it.
    append!(state.stack, parents(node))
    push!(state.seen, node)

    return (node, state)
end

iternodes(nodes::AbstractVector{<:Node}) = NodeIterator(Vector{Node}(nodes))

"""
    ancestors(nodes)

Get a list of all nodes in the graph defined by `nodes`, including all parents.
    * Every node in the graph will be visited exactly once.
    * The parents of any vertex will always come before the vertex itself.
"""
function ancestors(nodes::AbstractVector{<:Node})
    # Construct a LightGraphs representation of the whole node graph.
    node_to_vertex = Bijection(Dict(n => i for (i, n) in enumerate(iternodes(nodes))))

    # Initialising a SimpleDiGraph via an edge list is more efficient than calling add_edge!
    # repeatedly.
    #! format: off
    edges = Edge{Int64}[
        Edge(i, node_to_vertex[parent])
        for (node, i) in node_to_vertex
        for parent in parents(node)
    ]
    #! format: on
    light_graph = SimpleDiGraph(edges)

    # Suppose we have nodes with no parents on children in the graph - these will not show
    # up in the edge list, and may hence require manual addition.
    add_vertices!(light_graph, length(node_to_vertex) - nv(light_graph))

    vertices = [node_to_vertex[node] for node in nodes]
    ancestor_vertices = ancestors(light_graph, vertices)
    return [inverse(node_to_vertex, vertex) for vertex in ancestor_vertices]
end
