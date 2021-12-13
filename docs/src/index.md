```@meta
CurrentModule = TimeDag
```

# TimeDag

Welcome to the documentation for [TimeDag.jl](https://github.com/invenia/TimeDag.jl)!

`TimeDag` enables you to build and run time-series models efficiently.

You might want to use this package if some of the following apply:
* You are processing data with a natural time ordering.
* You need to handle data sources that update irregularly.
* You are building online-updating statistical models.
* Your input data is too large to fit in memory.
* Your system has several components that share similar computation.
* You want to create a real-time system, but also test it over a large historical dataset.

This package was built with Invenia's work in electricity grids in mind.
Other domains that could be suitable include sensor, system monitoring, and financial market data.

## Getting started

It might be helpful to begin with the [Concepts](@ref), and then to look at the [Examples](@ref).
After that, the documentation under `Reference->Node ops` should give an idea of what functionality is available.

## Roadmap

This section indicates various core functionality that is either possible, or in progress:

### Basic operations
- [x] Lagging by fixed number of knots
- [ ] Lagging by fixed time interval
- [x] Alignment of arbitrary numbers of node arguments to a node op

### Sources
- [x] In-memory, from an existing `Block`
- [x] From a Tea file
- [ ] From a generic `Table`, with some schema constraints

### Array-values
- [ ] Nodes should be aware of the `size` of each value, when it is provably constant.

### Statistics

- [x] Fixed-window sum, mean, std, cov, etc.
- [ ] Time-windowed sum, mean, standard-deviation, covariance, etc.
- [ ] Exponentially-weighted mean, std, cov, correlation
- [ ] Integration with [OnlineStats.jl](https://github.com/joshday/OnlineStats.jl) — should be easy to wrap an estimator into a node.

### Evaluation & scheduling
- [x] Single-threaded evaluation of a graph
- [ ] Optimise value-independent ops by using `alignment_base` concept.
- [ ] Graph compilation / [transformations](https://github.com/invenia/TimeDag.jl/issues/5)
- [ ] Parallel evaluation of a batch within time-independent nodes
- [ ] Parallelising scheduler