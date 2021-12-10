# TimeDag

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://invenia.github.io/TimeDag.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://invenia.github.io/TimeDag.jl/dev)
[![Build Status](https://github.com/invenia/TimeDag.jl/workflows/CI/badge.svg)](https://github.com/invenia/TimeDag.jl/actions)
[![Coverage](https://codecov.io/gh/invenia/TimeDag.jl/branch/main/graph/badge.svg?token=NpXA7RCBxc)](https://codecov.io/gh/invenia/TimeDag.jl)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)
[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-Contributor's%20Guide-blueviolet)](https://github.com/SciML/ColPrac)

A computational graph for time-series processing.

```julia
using Dates
using Statistics
using TimeDag

# Create nodes — lazy generators of time-series data.
x = rand(pulse(Hour(2)))
y = rand(pulse(Hour(3)))

# Apply functions to nodes to make new nodes.
z = cov(x, lag(y, 2))

# Evaluate nodes over a time range to pull data through the graph.
evaluate(z, DateTime(2021, 1, 1, 0), DateTime(2021, 1, 1, 15))
```

```
Block{Float64}(5 knots)
|                time |      value |
|            DateTime |    Float64 |
|---------------------|------------|
| 2021-01-01T08:00:00 |        0.0 |
| 2021-01-01T09:00:00 |  0.0245348 |
| 2021-01-01T10:00:00 |  0.0100269 |
| 2021-01-01T12:00:00 | 0.00183812 |
| 2021-01-01T14:00:00 | 0.00559926 |
```

For more information and examples, see the [documentation](https://invenia.github.io/TimeDag.jl/stable).
