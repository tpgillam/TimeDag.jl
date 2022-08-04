"""
    abstract type NodeOp{T} end

Represent a time-series operation whose output will be a time-series with value type `T`.
"""
abstract type NodeOp{T} end

"""
    Node(parents, op)

A node in the computational graph that combines zero or more `parents` with `op` to produce
a timeseries.

!!! warning
    Note that a `Node` is only declared mutable so that we can attach finalizers to
    instances. This is required for the [`WeakIdentityMap`](@ref) to work.
    Nodes should NEVER actually be mutated!

Due to subgraph elimination, nodes that are equivalent should always be identical objects.
We therefore leave `hash` & `==` defined in terms of the `objectid`.
"""
mutable struct Node{T}
    parents::NTuple{N,Node} where {N}
    op::NodeOp{T}
end

# Node & NodeOps are immutable for duplication purposes.
duplicate_internal(x::Node, ::IdDict) = x
duplicate_internal(x::NodeOp, ::IdDict) = x

Base.show(io::IO, node::Node) = show(io, node.op)

# Enable AbstractTrees to understand the graph.
# TODO It might be nice to elide repeated subtrees. This would require modifying the
#   iteration procedure within AbstractTrees, so ostriching for now.
AbstractTrees.children(node::Node) = parents(node)
AbstractTrees.nodetype(::Node) = Node

"""
    value_type(node::Node{T}) -> T

The type of each value emitted for this node.
"""
value_type(::Node{T}) where {T} = T
value_type(::NodeOp{T}) where {T} = T

"""
    abstract type NodeEvaluationState end

Represents any and all state that a node must retain between evaluating batches.

Instances of subtypes of `NodeEvaluationState` are given to [`run_node!`](@ref).
"""
abstract type NodeEvaluationState end

"""
    EmptyNodeEvaluationState()

A [`NodeEvaluationState`](@ref) which has no content, to be used by non-stateful nodes.

In practice, the common instance [`TimeDag.EMPTY_NODE_STATE`](@ref) can be used.
"""
struct EmptyNodeEvaluationState <: NodeEvaluationState end

# Can have a singleton instance, since it is just a placeholder.
"""
    const EMPTY_NODE_STATE

A singleton instance of [`TimeDag.EmptyNodeEvaluationState`](@ref).
"""
const EMPTY_NODE_STATE = EmptyNodeEvaluationState()

"""
    parents(node::Node) -> NTuple{N, Node} where {N}

Get immediate parents of the given node.
"""
parents(node::Node) = node.parents

"""
    create_evaluation_state(node::Node) -> NodeEvaluationState
    create_evaluation_state(parents, node::NodeOp) -> NodeEvaluationState

Create an empty evaluation state for the given node, when starting evaluation at the
specified time.
"""
create_evaluation_state(node::Node) = create_evaluation_state(node.parents, node.op)

"""
    run_node!(
        op::NodeOp{T},
        state::NodeEvaluationState,
        time_start::DateTime,
        time_end::DateTime,
        input_blocks::Block...
    ) -> Block{T}

Evaluate the given node from `time_start` until `time_end`, with the initial `state`.
Zero or more blocks will be passed as an input; these correspond to the parents of a node,
and are passed in the same order as that returned by `parents(node)`.

We return a new [`Block`](@ref) of output knots from this node.

!!! warning
    The implementer of `run_node!` must ensure:
    * **No future peeking** occurs: i.e. that no output knot is dependent on input knots
        that occur subsequently.
    * **Correct time range**: all output timestamps must be in the interval
        `[time_start, time_end)`.
    * **Consistency**: Calling `run_node!` over a single interval should give the same
        result as calling it multiple times over a decomposition of that same interval.
        This is to ensure [`evaluate`](@ref) operates as intended when the `batch_interval`
        kwarg is provided.
    * **Determinism**: `run_node!` should *always* be fully deterministic. If a
        pseudo-random number generator is required, it should be held on the evaluation
        state.
"""
function run_node! end

"""
    stateless(node) -> Bool
    stateless(op) -> Bool

Returns true iff `op` can be assumed to be stateless; that is, if the node evaluation state
is [`TimeDag.EMPTY_NODE_STATE`](@ref).
"""
stateless(node::Node) = stateless(node.op)
stateless(::NodeOp) = false

"""
    duplicate(x)

Return an object that is equal to `x`, but fully independent of it.

Note that for any parts of `x` that `TimeDag` considers to be immutable (e.g. `Block`s),
this can return the identical object.

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
