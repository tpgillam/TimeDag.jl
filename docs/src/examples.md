# Examples

The following examples demonstrate some of the basic functionality in `TimeDag`.

## Concrete data
We represent concrete time-series data with instances of [`Block`](@ref).
Let's create one now, using daily price data for crude oil from [MarketData.jl](https://github.com/JuliaQuant/MarketData.jl).

```@example basic
using Dates
using MarketData: cl, timestamp, values
using Plots
using TimeDag
block = Block(DateTime.(timestamp(cl)), values(cl))
```

Above it is represented in a raw table-like form.[^1] 
We can see that this block has values of type `Float64`.
For `Block`s with numeric value types, we can use the included plot recipe to visualise them:

[^1]: A [`Block`](@ref) is compatible with `Tables.jl`, which means that it can be easily converted to a `DataFrame` or similar.

```@example basic
plot(block; label="CL price")
```

## Creating nodes
The core of `TimeDag` is a computational graph of [`TimeDag.Node`](@ref)s.
These nodes represent time-series, and how they should be computed in terms of other time-series.

We can create a node from the block of data we already have:

```@example basic
price = block_node(block)
```

The node knows its [`value_type`](@ref), which will be `Float64` (since the values will just be those of the block we created earlier).

```@example basic
value_type(price)
```

Now let's perform some computation — let's estimate the 50 day rolling standard deviation of returns.

We start by computing relative returns using [`lag`](@ref); given a price ``p_t`` at time ``t``, the return series is ``r_t = \frac{p_t - p_{t-1}}{p_{t-1}}``.
We then use [`Statistics.std`](@ref) to define an online standard deviation over the specified window.

```@example basic
returns = (price - lag(price, 1)) / lag(price, 1)
using Statistics
std_50 = std(returns, 50)
```

Whilst it isn't normally necessary to inspect the graph by hand, we can visualise it with `AbstractTrees.print_tree`.
This is often good enough for a simple text-based representation, but be aware that actually we have a graph, and not a tree.
In the output, the `Lag` node appears twice, however it is in fact _exactly the same object_.

```@example basic
using AbstractTrees
print_tree(std_50)
```

Now that we have defined our computation, we can evaluate it to form a concrete time-series.
We use [`evaluate`](@ref), and here we pass in a time range that covers all our input-data.

By evaluating both `returns` and `std_50` in the same call, note that we do not duplicate work.
(See [Advanced evaluation](@ref) for further discussion on this.)

```@example basic
returns_block, std_50_block = evaluate([returns, std_50], DateTime(2000), DateTime(2003))

plot(returns_block; alpha=0.5, label="returns")
plot!(std_50_block; label="50 day std")
```

## Other sources
The example so far has used a _source node_ that simply wraps data that is already held in memory.
More interesting cases are nodes that read or generate their data only when evaluated.

Here we use [`Base.rand`](@ref) to generate a stream of random numbers.
It produces a value whenever its argument ticks — in this case, [`iterdates`](@ref) will tick once a day at midnight.[^2]

[^2]: Note that `TimeDag`'s time axis doesn't include timezone information.
It is good practice to consider this time to always be in UTC.

```@example basic
x = rand(iterdates())
plot(evaluate(x, DateTime(2001), DateTime(2003)); label="[2001, 2003)")
plot!(evaluate(x, DateTime(2001), DateTime(2002)); label="[2001, 2002)")
```

There are a couple of interesting things to note here:
1. We can generate more data by evaluating over a longer range.
2. So long as we start at the same time, we get exactly the same random numbers.
This second property is a **general** property of node evaluation — repeated evaluation should always give the same answer.

Finally, we show the correlation for two random numbers over an expanding window.
As expected, it converges towards zero as more data is observed:
```@example basic
y = rand(iterdates())
correlation = cor(x, y)
plot(evaluate(correlation, DateTime(2001), DateTime(2002)); label="correlation")
```

Information on other source nodes included with `TimeDag` is available in [Sources](@ref).
If you wish to create your own source nodes, e.g. to read data directly from a database table, refer to [Creating sources](@ref).