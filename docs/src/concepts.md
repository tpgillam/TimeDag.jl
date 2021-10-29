# Concepts

This document explains some key concepts and terminology.

## Time-series

Within `TimeDag.jl`, a time-series ``x\ \in \mathcal{TS}`` is defined to be an ordered sequence of ``N`` time-value pairs:
```math
\begin{aligned}
x   &= \{(t_i, x_i)\ |\ i \in [1, N]\}\\
t_i &\in \mathcal{T}_x\ \forall i, \quad \mathcal{T}_x = [t_1, \infty) \subset \mathcal{T}\\
x_i &\in \mathcal{X}\ \forall i\\
t_i &> t_{i-1}\ \forall i.
\end{aligned}
```

Here we use ``\mathcal{T}`` to denote the type of "time".
In general, all we require is general is that there is a total order on ``\mathcal{T}`` — so thinking about it as a real number is a good analogy.
Concretely, we currently require that all times are instances of `DateTime`.

``\mathcal{T}_x`` is the semi-infinite interval bounded below by the time of the first pair.

We define the _value type_ of ``x`` to be the set ``\mathcal{X}`` above, and in practice this can be any Julia type.
`TimeDag.jl` stores time-series data in memory in the [`Block`](@ref) type.

### Functional interpretation
We can also consider ``x`` to be a function, ``x : \mathcal{T}_x \rightarrow \mathcal{X}``.
This would be written ``x(t) = \max_i\ x_i\ \textrm{s.t.}\ t_i <= t``.

Informally, this means that whenever we observe a value ``x_i``, the 'value of' the time-series is ``x_i`` until such time as we observe ``x_{i+1}``.

Sometimes it is useful to write ``x(t_{-})`` for some ``t_{-} \in \mathcal{T} \setminus \mathcal{T}_x``.
We define this to be ``\oslash`` for every time-series; a placeholder element that simply means "no value".

!!! info
    Note that time is _strictly increasing_, and repeated times are not permitted.
    This conceptual choice is necessary to consider ``x`` to be a map from time to value as above.
    Without this restriction, there is an ambiguity whenever a time is repeated.

## Functions of time-series

### General case
We wish to define a general notion of a function ``f : \mathcal{TS} \times \cdots \times \mathcal{TS} \rightarrow \mathcal{TS}``.
Let ``z = f(x, y, \ldots)``, where ``x``, ``y`` and ``z`` are all time-series.

The only requirement we place is that each value ``z_i`` at time ``t_i`` can be written as the result of a function ``f'``:
```math
z_i = f'(t_i, \{z_1, \ldots, z_{i-1}\}, \{x(t) | t <= t_i\}, \{y(t) | t <= t_i\}, \ldots)
```

Let us unpack this a bit, informally speaking:
* We are only allowed to depend on _non-future_ values of ``x`` and ``y``.
* ``z`` can emit values at whatever times it likes, regardless of ``x`` and ``y``.
* The computation of values can be "stateful", in that it depends on past values that were computed.
* The value emitted can be a function of time.

The first of these is an important requirement, and `TimeDag.jl` aims to enforce this structurally.

### Explicit state
It is useful to re-write this a little by introducing the notion of a 'state' ``\zeta_i``:
```math
\begin{aligned}
z_i, \zeta_i &= f_v(t_i, \zeta_{i-1}, x(t_i), y(t_i), \ldots)\\
\end{aligned}
```
Each state ``\zeta_{i-1}`` needs to package as much information about the history of the inputs as necessary to compute each ``z_i`` (as well as the new state ``\zeta_i``).

!!! info
    It is useful to emphasise the distinction between these two functions:
    * ``f`` represents a time-series operation.
    * ``f_v`` represents the _implementation_ of ``f``.

    Certain choices of ``f`` allow us to reason about their semantics independently from their implementation.
    This is a useful separation of concerns.

### Parameters
In the above discussion, all arguments to ``f`` are time-series.
Such functions could additionally have some other non-time-series constant parameters, which we will denote ``\theta\in\Theta``.
Strictly mathematically, note that a "constant" can just be viewed as a time-series with a single observation at ``min \mathcal{T}``; so the above description is still fully general.

In practice (for efficient implementation) we will want function ``f : \Theta \times \mathcal{TS} \times \cdots \rightarrow \mathcal{TS}``.
So, ``f(\theta, x, y, \ldots)`` then has some constant parameter(s) ``\theta``.

## Special cases of functions

All time-series functions in `TimeDag.jl` are of the form of ``f`` above.
There are a few special cases, as well as specific examples, that are worth mentioning.

### Zero inputs

A function ``f : \Theta \rightarrow \mathcal{TS}`` can be considered a _source_ — that is, it generates a time-series for no time-series inputs.

Functions of this form 

### Alignment

TODO
Immediately, we note that ``\mathcal{T}_z \subset \mathcal{T}_x \cup \mathcal{T}_y``.
That is, ``z(t)`` can only be defined 

## Batched functions


## Implementation in TimeDag

Concretely in `TimeDag.jl`, the function ``g`` above would be a [`TimeDag.NodeOp`](@ref).

Under the hood, these are implemented with functions like ``g_
You will need to write something like ``g_v`` in order to _implement_ a new ``g``.
TODO

