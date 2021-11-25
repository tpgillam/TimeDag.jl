# Fundamentals

## Data

Time-series data is stored internally in a [`Block`](@ref).
More information on what we mean by a time-series is explained in [Time-series](@ref).

```@docs
Block
```

## Computational graph

The computational graph is formed of [`TimeDag.Node`](@ref) objects.
A node is an abstract representation of a time-series, i.e. a sequence of `(time, value)` pairs.
A node knows the type of its values, which can be queries with [`TimeDag.value_type`](@ref).

Note that nodes should never be constructed directly by the user.
Typically one will call a function like [`block_node`](@ref) or [`lag`](@ref), which will construct a node.

`TimeDag` includes functions to construct many useful nodes, but often you will need to create a custom node.
See `Creating nodes` for instructions on how to do this.

!!! info
    All nodes should eventually be constructed with [`TimeDag.obtain_node`](@ref).
    This uses the global [Identity map](@ref) to ensure that we do not duplicate nodes.

```@docs
TimeDag.Node
TimeDag.value_type
```

Every node contains parents, and a [`TimeDag.NodeOp`](@ref).

```@docs
TimeDag.NodeOp
TimeDag.obtain_node
```

Given a node, a rough-and-ready way to visualise the graph on the command line is with `AbstractTrees.print_tree`.
This will not directly indicated repeated nodes, but for small graphs the output can be useful.

## Evaluation

In order to get a concrete time-series (as a [`Block`](@ref)) for a node, it must be evaluated with [`evaluate`](@ref).
Evaluation additionally requires a time range, and involves pulling data corresponding to this interval through the graph of ancestors of the given node(s).

!!! tip
    When evaluating a graph in a production system, it may be desirable to have more control over evaluation.
    If this sounds like you, please read the [Advanced evaluation](@ref) section!

```@docs
evaluate
```