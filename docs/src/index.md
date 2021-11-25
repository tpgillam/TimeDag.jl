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