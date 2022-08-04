# Internals

This page documents internal, and less commonly-used API.
Some of it will be useful for users for more advanced use-cases, like running graphs in production systems.
Other parts shouldn't need to be regularly interacted with, but can be useful to know about.

## Identity map

One of the key features of `TimeDag` is avoiding duplicating work.

This is primarily achieved by ensuring that we never construct the 'same' node twice.
By 'same', here we mean two nodes that we can prove will always give the same output.

One easy-to-handle case is that of a node that has identical parents & op to another.
To avoid this, `TimeDag` maintains a global [identity map](https://en.wikipedia.org/wiki/Identity_map_pattern), of type [`TimeDag.IdentityMap`](@ref).

Currently the only implementation of the identity map is [`TimeDag.WeakIdentityMap`](@ref).
This contains weak references to nodes, to ensure that we know about all nodes that currently exist, but don't unnecessarily prevent nodes from being garbage collected when we no longer want them.

In practice, all nodes should be constructed indirectly using [`TimeDag.obtain_node`](@ref). 
This will query the `global_identity_map()`, and only construct a new node if an equivalent one does not already exist.

```@docs
TimeDag.IdentityMap
TimeDag.obtain_node!
TimeDag.global_identity_map
TimeDag.WeakNode
TimeDag.WeakIdentityMap
```

## Advanced evaluation

This section goes into more detail about how evaluation works. 
We explain evaluation state, and discuss how to use the API in a [Live system](@ref).

### Evaluation state

Recall from the discussion in [Concepts](@ref) that we have the concept of [Explicit state](@ref).
For a particular node, this state will be a subtype of [`TimeDag.NodeEvaluationState`](@ref).
For consistency, all nodes have an evaluation state — for nodes that are fundamentally stateless, we use [`TimeDag.EMPTY_NODE_STATE`](@ref).

A fresh evaluation state is created by a call to [`TimeDag.create_evaluation_state`](@ref).
When creating a new [`TimeDag.NodeOp`](@ref), a new method of this function should be defined to return the appropriate state.
The state is subsequently mutated in calls [`TimeDag.run_node!`](@ref), to reflect any changes induced over the time interval.

```@docs
TimeDag.NodeEvaluationState
TimeDag.EmptyNodeEvaluationState
TimeDag.EMPTY_NODE_STATE
TimeDag.create_evaluation_state
TimeDag.stateless
TimeDag.run_node!
```

When an evaluation is performed, we need to save the state of all the nodes in the graph.
We package this into an [`TimeDag.EvaluationState`](@ref) instance.
This object also retains the blocks from the nodes in whose output we're interested.

```@docs
TimeDag.EvaluationState
```

### Deconstructing evaluation

Whilst [`evaluate`](@ref) is the primary API for `TimeDag`, it is in fact a thin wrapper around a lower level API.
Roughly, the steps involved are:
1. Call [`TimeDag.start_at`](@ref) to create a new [`TimeDag.EvaluationState`](@ref) for a collection of nodes.
    This will work out all the ancestors of the given nodes that also need to be evaluated.
1. Perform one or more calls to [`TimeDag.evaluate_until!`](@ref), depending on the batch interval.
    Each call will update the evaluation state.
    Interenally, this calls [`TimeDag.run_node!`](@ref) for every ancestor node.
1. Once the end of the evaluation interval has been reached, we extract the blocks for the nodes of interest from the evaluation state.
    These are concatenated and returned to the user.

```@docs
TimeDag.start_at
TimeDag.evaluate_until!
```

#### Live system
Consider the case where some history of data is available, say in a database, and new data is added continually, e.g. as it is recorded from a sensor.
Suppose we have built a `TimeDag` graph representing the computation we wish to perform on this data.
We can perform the following steps:
1. Initialise the state with [`TimeDag.start_at`](@ref).
1. Initialise the model with one (or more) calls to [`TimeDag.evaluate_until!`](@ref).
    This is used to pull through historical data, e.g. to initialise stateful nodes like moving averages.
1. In real time, poll for new data with repeated calls to [`TimeDag.evaluate_until!`](@ref)

The performance of this setup is naturally dependent upon the complexity of the model being evaluated.
However, if models are appropriately designed to have efficient online updates, then the underlying overhead of `TimeDag` is sufficiently small for this to be usable with latencies of down to O(milliseconds).

```@example
using Dates  # hide
using Statistics  # hide
using TimeDag  # hide
# Some arbitrary data source - here just use random numbers.
x = rand(pulse(Second(1)))

# Compute a rolling mean and standard deviation.
# Corresponds to 24-hour rolling windows, given one data point per second.
n1, n2 = mean(x, 86400), std(x, 86400)

# Initialise state over a long history.
state = TimeDag.start_at([n1, n2], DateTime(2019))
state = TimeDag.evaluate_until!(state, DateTime(2020))

# Simulate an incremental update over a few hours.
@time state = TimeDag.evaluate_until!(state, DateTime(2020, 1, 1, 3))
nothing  # hide
```

Note that this approach is unlikely to be suitable for lower latency applications (e.g. microseconds).
For that case, one may benefit from a "push mode" evaluation, where new data are pushed onto the graph, and only affected nodes are re-evaluated.
Such a feature isn't currently planned.

### Scheduling

`TimeDag` currently runs all nodes in a single thread, however this is subject to change in the future.

## Alignment implementation

If we want to define a new op that follows alignment semantics, it should derive from one of the following types.

```@docs
TimeDag.UnaryNodeOp
TimeDag.BinaryNodeOp
TimeDag.NaryNodeOp
```

Instead of implementing [`TimeDag.run_node!`](@ref) directly, one instead implements some of the following functions.
The exact alignment logic is then encapsulated, and doesn't need to be dealt with directly.

```@docs
TimeDag.operator!
TimeDag.always_ticks
TimeDag.stateless_operator
TimeDag.time_agnostic
TimeDag.value_agnostic
TimeDag.has_initial_values
TimeDag.initial_left
TimeDag.initial_right
TimeDag.initial_values
TimeDag.create_operator_evaluation_state
```

For simple cases, the following node ops can be useful.

!!! tip
    Rather than using the structures below directly, you probably want to use [`TimeDag.apply`](@ref), [`wrap`](@ref), or [`wrapb`](@ref).

```@docs
TimeDag.SimpleUnary
TimeDag.SimpleBinary
TimeDag.SimpleBinaryUnionInitial
TimeDag.SimpleBinaryLeftInitial
TimeDag.SimpleNary
TimeDag.SimpleNaryInitial
```

## Maybe

```@docs
TimeDag.Maybe
TimeDag.valid
TimeDag.value
TimeDag.unsafe_value
```

## Other

```@docs
TimeDag.output_type
TimeDag.duplicate
```
