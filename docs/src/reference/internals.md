# Internals

This page documents internal, and less commonly-used API.
Some of it will be useful for users for more advanced use-cases, like running graphs in production systems.
Other parts shouldn't need to be regularly interacted with, but can be useful to know about.

## Identity map

One of the key features of `TimeDag.jl` is avoiding duplicating work.

This is primarily achieved by ensuring that we never construct the 'same' node twice.
By 'same', here we mean two nodes that we can prove will always give the same output.

One easy-to-handle case is that of a node that has identical parents & op to another.
To avoid this, `TimeDag.jl` maintains a global [identity map](https://en.wikipedia.org/wiki/Identity_map_pattern), of type [`TimeDag.IdentityMap`](@ref).

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

Sometimes [`evaluate`](@ref) does not provide enough control.
This section goes into more detail about how evaluation works, and in particular how this can be useful for live systems.

### Evaluation state

### Batching


### Scheduling


```@docs
TimeDag.EvaluationState
TimeDag.NodeEvaluationState
TimeDag.start_at
TimeDag.evaluate_until!
TimeDag.run_node!
```

## Other

```@docs
TimeDag.output_type
TimeDag.duplicate
```