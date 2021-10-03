"""
Represent a node-like object, that doesn't hold strong references to its parents.

This exists purely such that `hash` and `==` *do* allow multiple instances of
`WeakNode` to compare equal if they have the same `parents` and `op`.
"""
struct WeakNode
    parents::NTuple{N,WeakRef} where {N}
    op::NodeOp
end
WeakNode(node::Node) = WeakNode(map(WeakRef, node.parents), node.op)

# Weak nodes need to have hash & equality defined such that instances with equal
# parents and op compare equal. This will be relied upon in `obtain_node` later.
Base.hash(a::WeakNode, h::UInt) = hash(a.op, hash(a.parents, hash(:WeakNode, h)))
function Base.isequal(a::WeakNode, b::WeakNode)
    isequal(a.parents, b.parents) && isequal(a.op, b.op)
end

"""
Represent a graph of nodes which doesn't hold strong references to any nodes.

This is useful, as it allows the existence of this graph to be somewhat transparent to the
user, and they only have to care about holding on to references for nodes that they care
about.

This structure contains nodes, but also node weak nodes -- this allows us to determine
whether we ought to create a given node.

Note that this structure is definitely *not* threadsafe. We are assuming that all nodes are
created in a single thread.
"""
mutable struct NodeGraph
    # TODO This could be wrapped up into a WeakBijection data structure, which would
    #   potentially allow for more efficient handling of nodes going out of scope.
    node_to_weak::WeakKeyDict{Node,WeakNode}
    weak_to_ref::Dict{WeakNode,WeakRef}
    dirty::Bool
    finalizer::Function

    function NodeGraph()
        graph = new(WeakKeyDict(), Dict(), false)
        graph.finalizer = _ -> graph.dirty = true
        return graph
    end
end

Base.length(graph::NodeGraph) = length(graph.node_to_weak)
Base.isempty(graph::NodeGraph) = length(graph) == 0

function _cleanup!(graph::NodeGraph)
    graph.dirty || return nothing

    # We need to clean up stale entries from weak_to_ref.
    graph.dirty = false

    # This is analogous to the implementation in WeakKeyDict.
    # Note that we use hidden functionality of Dict here. This is because we can no longer
    # rely on the keys to be a good indexer, since they contain weak references that may
    # have gone stale
    idx = Base.skip_deleted_floor!(graph.weak_to_ref)
    while idx != 0
        if graph.weak_to_ref.vals[idx].value === nothing
            Base._delete!(graph.weak_to_ref, idx)
        end
        idx = Base.skip_deleted(graph.weak_to_ref, idx + 1)
    end
end

"""
    _insert_node!(graph::NodeGraph, node, weak_node) -> NodeGraph

Insert `node` & equivalent `weak_node` into `graph`.
"""
function _insert_node!(graph::NodeGraph, node::Node, weak_node::WeakNode)
    # Insert the node & its weak counterpart to the mappings.
    graph.node_to_weak[node] = weak_node
    graph.weak_to_ref[weak_node] = WeakRef(node)

    # Add a finalizer to the node that will declare the graph to be dirty when it is
    # deleted. We handle this above.
    finalizer(graph.finalizer, node)

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
function obtain_node(graph::NodeGraph, parents::NTuple{N,Node}, op::NodeOp) where {N}
    if !isempty(parents) && _can_propagate_constant(op) && all(_is_constant, parents)
        # Constant propagation, since all inputs are constants & the op supports it.
        # Note that `constant` does, itself, call through to `obtain_node`, so the node will
        # be correctly registered with the graph.
        return constant(_propagate_constant_value(op, parents))
    end

    # Before attempting to query or modify the graph, ensure it is free of dangling
    # references.
    _cleanup!(graph)

    weak_node = WeakNode(map(WeakRef, parents), op)
    node_ref = get(graph.weak_to_ref, weak_node, nothing)
    return if !isnothing(node_ref)
        # Remember that we need to unwrap the value from the WeakRef...
        node_ref.value
    else
        # An equivalent node does not yet exist in the graph; create it
        node = Node(parents, op)
        _insert_node!(graph, node, weak_node)
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

"""
    ancestors(graph, nodes...) -> Vector{Node}
    ancestors(nodes...)

Get a list of all nodes in the graph defined by `nodes`, including all parents.
    * Every node in the graph will be visited exactly once.
    * The parents of any vertex will always come before the vertex itself.

If `graph` is not specified, the global graph will be used.
"""
function ancestors(graph::NodeGraph, nodes::Node...)
    # Construct a LightGraphs representation of the whole node graph.
    node_to_vertex = Bijection(
        Dict(n => i for (i, n) in enumerate(keys(graph.node_to_weak)))
    )
    light_graph = SimpleDiGraph(length(graph))
    for (node, i) in node_to_vertex
        for parent in parents(node)
            # Add edge from node to parent.
            add_edge!(light_graph, i, node_to_vertex[parent])
        end
    end

    vertices = [node_to_vertex[node] for node in nodes]
    ancestor_vertices = ancestors(light_graph, vertices)
    return [inverse(node_to_vertex, vertex) for vertex in ancestor_vertices]
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
