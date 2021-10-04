"""
Represent a node-like object, that doesn't hold strong references to its parents.

This exists purely such that `hash` and `==` *do* allow multiple instances of
`WeakNode` to compare equal if they have the same `parents` and `op`.
"""
struct WeakNode
    parents::NTuple{N,WeakRef} where {N}
    op::NodeOp
end

# Weak nodes need to have hash & equality defined such that instances with equal
# parents and op compare equal. This will be relied upon in `obtain_node` later.
Base.hash(a::WeakNode, h::UInt) = hash(a.op, hash(a.parents, hash(:WeakNode, h)))
function Base.isequal(a::WeakNode, b::WeakNode)
    return isequal(a.parents, b.parents) && isequal(a.op, b.op)
end

# FIXME
#   If the WeakIdentityMap can't be made to work on 1.5, we could have two identity maps:
#       * WeakIdentityMap  (default on 1.6+)
#       * StrongIdentityMap (default otherwise)
#
#   The latter will hold onto strong references. It will avoid much of the complexity at
#   the expense of remembering every node ever created, which would get bad quickly.
#
#   Could *maybe* also have:
#       * NullIdentityMap  (no id-mapping)
#   if this doesn't break assumptions elsewhere (it would always create new nodes).

abstract type IdentityMap end

"""
Represent a collection of nodes which doesn't hold strong references to any nodes.

This is useful, as it allows the existence of this cache to be somewhat transparent to the
user, and they only have to care about holding on to references for nodes that they care
about.

This structure contains nodes, but also node weak nodes -- this allows us to determine
whether we ought to create a given node.
"""
mutable struct WeakIdentityMap <: IdentityMap
    # TODO This could be wrapped up into a WeakValueDict data structure, which would
    #   potentially allow for more efficient handling of nodes going out of scope.
    weak_to_ref::Dict{WeakNode,WeakRef}
    lock::ReentrantLock
    dirty::Bool
    finalizer::Function

    function WeakIdentityMap()
        id_map = new(Dict(), ReentrantLock(), false)
        id_map.finalizer = _ -> id_map.dirty = true
        return id_map
    end
end

Base.lock(f, id_map::WeakIdentityMap) = lock(f, id_map.lock)

function _cleanup!(id_map::WeakIdentityMap)
    id_map.dirty || return nothing

    # We need to clean up stale entries from weak_to_ref.
    id_map.dirty = false

    # This is analogous to the implementation in WeakKeyDict.
    # Note that we use hidden functionality of Dict here. This is because we can no longer
    # rely on the keys to be a good indexer, since they contain weak references that may
    # have gone stale
    idx = Base.skip_deleted_floor!(id_map.weak_to_ref)
    while idx != 0
        if id_map.weak_to_ref.vals[idx].value === nothing
            Base._delete!(id_map.weak_to_ref, idx)
        end
        idx = Base.skip_deleted(id_map.weak_to_ref, idx + 1)
    end
end

function Base.length(id_map::WeakIdentityMap)
    return lock(id_map) do
        _cleanup!(id_map)
        length(id_map.weak_to_ref)
    end
end
Base.isempty(id_map::WeakIdentityMap) = length(id_map) == 0

function all_nodes(id_map::WeakIdentityMap)
    return lock(id_map) do
        _cleanup!(id_map)
        Node[x.value for x in values(id_map.weak_to_ref)]
    end
end

"""
    _insert_node!(id_map::WeakIdentityMap, node, weak_node) -> WeakIdentityMap

Insert `node` & equivalent `weak_node` into `id_map`.
"""
function _insert_node!(id_map::WeakIdentityMap, node::Node, weak_node::WeakNode)
    # Insert the node & its weak counterpart to the mappings.
    id_map.weak_to_ref[weak_node] = WeakRef(node)

    # Add a finalizer to the node that will declare the id_map to be dirty when it is
    # deleted. We handle this above.
    finalizer(id_map.finalizer, node)

    return id_map
end

function obtain_node!(
    id_map::WeakIdentityMap, parents::NTuple{N,Node}, op::NodeOp
) where {N}
    # FIXME So so so so slow on 1.6.
    #   On 1.5, this adds *even more* failures (of the form of obtaining nodes, and them
    #   ending up being `nothing`.)
    # GC.gc()
    return lock(id_map) do
        # FIXME This results in tests breaking! Excellent...
        #   It looks reminiscent of the failures seen on Julia 1.5
        #   This looks relevant: https://github.com/JuliaLang/julia/pull/38487
        #   It changed the behaviour of finalizers so that they didn't run when locks
        #   had been acquired.
        # GC.gc()

        # Before attempting to query or modify the id_map, ensure it is free of dangling
        # references.
        _cleanup!(id_map)

        weak_node = WeakNode(map(WeakRef, parents), op)
        node_ref = get(id_map.weak_to_ref, weak_node, nothing)
        if !isnothing(node_ref)
            # Remember that we need to unwrap the value from the WeakRef...
            # FIXME This value can be nothing because of some horrible race condition.
            node_ref.value
        else
            # An equivalent node does not yet exist in the id_map; create it.
            node = Node(parents, op)
            _insert_node!(id_map, node, weak_node)
            node
        end
    end
end

# This is the single instance of the id_map that we want
const _GLOBAL_IDENTITY_MAP = WeakIdentityMap()

"""
    global_identity_map() -> IdentityMap

Get the global IdentityMap instance used in TimeDag.
"""
global_identity_map() = _GLOBAL_IDENTITY_MAP
