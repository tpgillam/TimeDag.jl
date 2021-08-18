"""
Represent a graph of nodes which doesn't hold strong references to any nodes.

This is useful, as it allows the existence of this graph to be somewhat transparent to the
user, and they only have to care about holding on to references for nodes that they care
about.

Note that this structure is definitely *not* threadsafe. We are assuming that all nodes are
created in a single thread.
"""
mutable struct NodeGraph
    node_to_vertex::WeakKeyDict{Node, Int64}
    vertex_to_ref::Dict{Int64, WeakRef}
    # TODO Figure out of this LightGraph representation is useful.
    # Edges are directed from parents to children.
    graph::SimpleDiGraph{Int64}
    dirty::Bool  # This means that `vertex_to_ref` needs cleaning.
end
NodeGraph() = NodeGraph(WeakKeyDict(), Dict(), SimpleDiGraph(), false)

Base.length(graph::NodeGraph) = length(graph.node_to_vertex)
Base.isempty(graph::NodeGraph) = length(graph) == 0
Base.haskey(graph::NodeGraph, node::Node) = haskey(graph.node_to_vertex, node)

function _cleanup(graph::NodeGraph)
    if graph.dirty
        # Clean up any dangling references in vertex_to_ref.
        graph.dirty = false

        # This does a full scan. This is a bit sad, although in practice we shouldn't do it
        # especially often (as hopefully we rarely throw away nodes in typical usage).
        for (key, ref) in graph.vertex_to_ref
            if isnothing(ref.value)
                delete!(graph.vertex_to_ref, key)
                # TODO Remove index from graph too? -- actually CAREFUL about this, as the
                # default LightGraph implementation will then relabel the last vertex so as
                # to preserve contiguity.
                # Probably simpler to leave dangling for now, but in the future we should
                # think about solving this more nicely.
            end
        end
    end
end

function insert_node!(graph::NodeGraph, node::Node)
    _cleanup(graph)

    if haskey(graph, node)
        # Nothing to do!
        return
    end

    # We are going to add the node - we must do the following:
    #   1. Figure out what index the node should have
    add_vertex!(graph.graph)
    index = nv(graph.graph)

    #   2. Insert into A & B
    graph.node_to_vertex[node] = index
    graph.vertex_to_ref[index] = WeakRef(node)

    #   3. Add a finalizer to node that will declare the graph to be dirty when it is
    #       deleted. We handle this above.
    finalizer(n -> graph.dirty = true, node)

    # Insert all parents.
    for parent in parents(node)
        insert_node!(graph, parent)
        # Add edge from node to parent.
        add_edge!(graph.graph, graph.node_to_vertex[node], graph.node_to_vertex[parent])
    end
    return graph
end

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
    obtain_node(graph::NodeGraph, parents, op::NodeOp) -> Node
    obtain_node(parents, op) -> Node

Get a node for the given NodeOp and parents. If an equivalent node already exists in the
graph, use that one, otherwise create a new node, add to the graph, and return it.

If the graph is not specified, the global graph is used.
"""
function obtain_node(graph::NodeGraph, parents::NTuple{N, Node}, op::NodeOp) where {N}
    if !isempty(parents) && _can_propagate_constant(op) && all(_is_constant, parents)
        # Constant propagation, since all inputs are constants & the op supports it.
        return constant(_propagate_constant_value(op, parents))
    end
    node = Node(parents, op)
    return if haskey(graph, node)
        # An equivalent node exists in the graph; return the existing node.
        index = graph.node_to_vertex[node]
        # Remember that we need to unwrap the value from the WeakRef...
        graph.vertex_to_ref[index].value
    else
        # Insert the new node into the graph, and return it.
        insert_node!(graph, node)
        node
    end
end

function obtain_node(graph::NodeGraph, parents::AbstractVector{Node}, op::NodeOp)
    return obtain_node(graph, op, Tuple(parents))
end

"""
    ancestors(graph::AbstractGraph{T}, sources::AbstractVector{T}) -> Vector{T}

Given a (directed) graph, with edges from child to parent, find all ancestor vertices of the
given `sources`.

The result will be ordered such that the parents of any given vertex will always come before
the vertex itself.
"""
function ancestors(graph::AbstractGraph{T}, sources::AbstractVector{T}) where {T}
    if isempty(sources)
        throw(ArgumentError("Need at least 1 source"))
    end

    seen = Set{T}()

    stack = Vector(sources)
    # results = [[source] for source in sources]

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

"""
    ancestors(graph, nodes...) -> Vector{Node}
    ancestors(nodes...)

Get a list of all nodes in the graph defined by `nodes`, including all parents.
    * Every node in the graph will be visited exactly once.
    * The parents of any vertex will always come before the vertex itself.

If `graph` is not specified, the global graph will be used.
"""
function ancestors(graph::NodeGraph, nodes::Node...)
    vertices = [graph.node_to_vertex[node] for node in nodes]
    ancestor_vertices = ancestors(graph.graph, vertices)
    return [graph.vertex_to_ref[vertex].value for vertex in ancestor_vertices]
end


# This is the single instance of the graph that we want
const _GLOBAL_GRAPH = NodeGraph()

"""
    global_graph() -> NodeGraph

Get the global NodeGraph instance used in TimeDag.
"""
global_graph() = _GLOBAL_GRAPH

obtain_node(parents, op::NodeOp) = obtain_node(_GLOBAL_GRAPH, parents, op)
ancestors(nodes::Node...) = ancestors(_GLOBAL_GRAPH, nodes...)
