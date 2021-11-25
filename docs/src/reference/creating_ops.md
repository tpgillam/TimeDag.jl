# Creating operations

Sometimes the operations contained in `TimeDag` will not be sufficient.
This document explains how new operations can be created.

## Standard alignment behaviour
In many cases, one wishes to write an op that specifies how to process one or more input values, whilst using default alignment semantics. 
In this case, one should use [`TimeDag.apply`](@ref), [`wrap`](@ref) or [`wrapb`](@ref).

```@docs
TimeDag.apply
wrap
wrapb
```

## Creating sources

In order to create a source — i.e. an op with zero inputs — one should use the [Low-level API](@ref).

## Low-level API

The most general way to create an op is to create a structure that inherits from [`TimeDag.NodeOp`](@ref), and implement [`TimeDag.run_node!`](@ref).
One must use this to implement source nodes, but in other cases it is typically preferable to use [Standard alignment behaviour](@ref).
This is because there are number of rules that must be adhered to when implementing [`TimeDag.run_node!`](@ref), as noted in its docstring. 

### Example: stateless source
Here is stateless source node, which is effectively a simplified [`iterdates`](@ref):

```julia
struct MySource <: TimeDag.NodeOp{Int64} end

# Indicate that our source doesn't have any evaluation state.
TimeDag.stateless(::MySource) = true

function TimeDag.run_node!(
    ::MySource, 
    ::TimeDag.EmptyNodeEvaluationState, 
    time_start::DateTime, 
    time_end::DateTime,
)
    # We must return a Block with data covering the interval [time_start, time_end).
   
    # Here we define a node which ticks every day at midnight.
    t1 = Date(time_start) + Time(0)
    t1 = t1 < time_start ? t1 + Day(1) : t1

    # Figure out the last time to emit.
    t2 = Date(time_end) + Time(0)
    t2 = t2 >= time_end ? t2 - Day(1) : t2

    # For no particular reason, we 
    times = t1:Day(1):t2
    values = ones(length(times))
    return Block(times, values)
end
```
