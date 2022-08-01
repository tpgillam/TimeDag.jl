_left(x, _) = x
_right(_, y) = y

# TODO We should add the concept of alignment_base, i.e. an ancestor that provably has the
#   same alignment as a particular node. This can allow for extra pruning of the graph.

"""
    left(x, y[, alignment::Alignment; initial_values=nothing]) -> Node

Construct a node that ticks according to `alignment` with the latest value of `x`.

It is "left", in the sense of picking the left-hand of the two arguments `x` and `y`.
"""
function left(x, y, alignment::Alignment=DEFAULT_ALIGNMENT; initial_values=nothing)
    x === y && return x
    return apply(_left, x, y, alignment; initial_values)
end

"""
    right(x, y[, alignment::Alignment; initial_values=nothing]) -> Node

Construct a node that ticks according to `alignment` with the latest value of `y`.

It is "right", in the sense of picking the right-hand of the two arguments `x` and `y`.
"""
function right(x, y, alignment::Alignment=DEFAULT_ALIGNMENT; initial_values=nothing)
    x === y && return x
    return apply(_right, x, y, alignment; initial_values)
end

"""
    align(x, y) -> Node

Form a node that ticks with the values of `x` whenever `y` ticks.
"""
align(x, y) = right(y, x, LEFT)

"""
    align_once(x, y) -> Node

Similar to `align(x, y)`, except knots from `x` will be emitted at most once.

This means that the resulting node will tick at a subset of the times that `y` ticks.
"""
function align_once(x, y)
    x = _ensure_node(x)
    y = _ensure_node(y)

    # Imagine the following scenario.
    #
    # x: 1  2  3     4  5
    # y: x     x  x     x
    #
    # In this situation, we want the result to be
    # z: 1     3        5
    #
    # We can directly implement this by working with the 'knot count', and filtering out
    # those knots where the count increases. We can then align to this.
    aligned_count = align(count_knots(x), y)

    # We should remove any knot where the change in count is non-positive.
    alignment = filter(>(0), prepend(aligned_count, diff(aligned_count)))
    return align(x, alignment)
end

# TODO support initial_values in coalign.
"""
    coalign(x, [...; alignment::Alignment]) -> Node...

Given at least one node(s) `x`, or values that are convertible to nodes, align all of them.

We guarantee that all nodes that are returned will have the same alignment. The values of
each node will correspond to the values of the input nodes.

The choice of alignment is controlled by `alignment`, which defaults to [`UNION`](@ref).
"""
function coalign(x, x_rest...; alignment::Alignment=DEFAULT_ALIGNMENT)
    x = map(_ensure_node, [x, x_rest...])

    # Deal with simple case where we only have one input. There is no aligning to do.
    length(x) == 1 && return only(x)

    # Find a well-defined ordering of the inputs -- this is an optimisation designed to
    # avoid creating equivalent nodes if `coalign` is called multiple times.
    # As such we use objectid. Strictly this is a hash, and so there could be clashes. We
    # accept this, since if such a clash were to occur it would result only in sub-optimal
    # performance, and most likely in a very minor way.
    index = if isa(alignment, LeftAlignment)
        # For left alignment we must leave the first node in place.
        [1; 1 .+ sortperm(@view(x[2:end]); by=objectid)]
    else
        sortperm(x; by=objectid)
    end
    x, x_rest... = x[index]

    # Construct one node with the correct alignment. This will also have the correct values
    # for the first node to return.
    for node in x_rest
        x = left(x, node, alignment)
    end

    # For all of the remaining nodes, align them.
    new_nodes = (x, (align(node, x) for node in x_rest)...)

    # Convert nodes back to original order.
    return new_nodes[invperm(index)]
end

struct FirstKnot{T} <: NodeOp{T} end

mutable struct FirstKnotState <: NodeEvaluationState
    ticked::Bool
    FirstKnotState() = new(false)
end

create_evaluation_state(::Tuple{Node}, ::FirstKnot) = FirstKnotState()

function run_node!(
    ::FirstKnot{T},
    state::FirstKnotState,
    time_start::DateTime,
    time_end::DateTime,
    block::Block{T},
) where {T}
    # If we have already ticked, or the input is empty, we should not emit any knots.
    (state.ticked || isempty(block)) && return Block{T}()

    # We should tick, and record the fact that we have done so.
    state.ticked = true
    time = @inbounds first(block.times)
    value = @inbounds first(block.values)
    return Block(unchecked, [time], T[value])
end

"""
    first_knot(x::Node{T}) -> Node{T}

Get a node which ticks with only the first knot of `x`, and then never ticks again.
"""
function first_knot(node::Node{T}) where {T}
    # This function should be idempotent for constant nodes.
    _is_constant(node) && return node
    return obtain_node((node,), FirstKnot{T}())
end

"""
    active_count(nodes...) -> Node{Int64}

Get a node of the number of the given `nodes` (at least one) which are active.
"""
function active_count(x, x_rest...)
    nodes = map(_ensure_node, [x, x_rest...])

    # Perform the same ordering optimisation that we use in coalign. This aims to give the
    # same node regardless of the order in which `nodes` were passed in.
    sort!(nodes; by=objectid)
    return reduce((x, y) -> +(x, y; initial_values=(0, 0)), align.(1, first_knot.(nodes)))
end

struct Prepend{T} <: NodeOp{T} end
mutable struct PrependState <: NodeEvaluationState
    switched::Bool
    PrependState() = new(false)
end
create_evaluation_state(::Tuple{Node,Node}, op::Prepend) = PrependState()
function run_node!(
    ::Prepend{T},
    state::PrependState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_x::Block,
    input_y::Block,
) where {T}
    # prepend is implemented in terms of the raw API, since conceptually there will only be
    # one batch where we have to find switch-over between nodes. This can be found with
    # binary search or similar. In prior & subsequent batches we can immediately use the
    # block from either x or y as appropriate.

    # If we've already switched, we just take input from y.
    state.switched && return input_y

    # We haven't already switched.
    # If y has not ticked, take input from x.
    isempty(input_y) && return input_x

    # We are in the block where y has some values.
    state.switched = true

    # Allocate a block of the maximum possible length. We'll trim it later.
    n = length(input_x) + length(input_y)
    times = _allocate_times(n)
    values = _allocate_values(T, n)

    # Index into the output.
    j = 1

    # Copy from x into the output buffer, until we want to take from y instead.
    switch_time = first(input_y.times)
    @inbounds for ix in 1:length(input_x)
        time = input_x.times[ix]
        # Stop copying values when we hit the first time in y.
        time >= switch_time && break

        times[j] = time
        values[j] = input_x.values[ix]
        j += 1
    end

    # Copy the remaining values from y into the output buffer.
    @inbounds for (time, value) in input_y
        times[j] = time
        values[j] = value
        j += 1
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)

    return Block(unchecked, times, values)
end

"""
    prepend(x, y) -> Node

Create a node that ticks with knots from `x` until `y` is active, and thereafter from `y`.

Note that the [`value_type`](@ref) of the returned node will be that of the promoted value
types of `x` and `y`.
"""
function prepend(x, y)
    x = _ensure_node(x)
    y = _ensure_node(y)

    # Constant propagation.
    _is_constant(x) && _is_constant(y) && return y

    T = promote_type(value_type(x), value_type(y))
    return obtain_node((x, y), Prepend{T}())
end

struct ThrottleKnots{T} <: UnaryNodeOp{T}
    n::Int64
end

time_agnostic(::ThrottleKnots) = true

"""
State to keep track of the number of knots that we have seen on the input since the last
output.
"""
mutable struct ThrottleKnotsState <: NodeEvaluationState
    count::Int64
    ThrottleKnotsState() = new(0)
end

create_operator_evaluation_state(::Tuple{Node}, ::ThrottleKnots) = ThrottleKnotsState()

function operator!(op::ThrottleKnots{T}, state::ThrottleKnotsState, x::T) where {T}
    result = if state.count == 0
        state.count = op.n
        Maybe(x)
    else
        Maybe{T}()
    end
    state.count -= 1
    return result
end

"""
    throttle(x::Node, n::Integer) -> Node

Return a node that only ticks every `n` knots.

The first knot encountered on the input will always be emitted.

!!! info
    The throttled node is stateful and depends on the starting point of the evaluation.
"""
function throttle(x::Node, n::Integer)
    n > 0 || throw(ArgumentError("n should be positive, got $n"))
    n == 1 && return x
    return obtain_node((x,), ThrottleKnots{value_type(x)}(n))
end

struct CountKnots <: UnaryNodeOp{Int64} end
time_agnostic(::CountKnots) = true
always_ticks(::CountKnots) = true

"""State to keep track of the number of knots that we have seen on the input."""
mutable struct CountKnotsState <: NodeEvaluationState
    count::Int64
    CountKnotsState() = new(0)
end

create_operator_evaluation_state(::Tuple{Node}, ::CountKnots) = CountKnotsState()

function operator!(::CountKnots, state::CountKnotsState, x::T) where {T}
    state.count += 1
    return state.count
end

"""
    count_knots(x) -> Node{Int64}

Return a node that ticks with the number of knots seen in `x` since evaluation began.
"""
function count_knots(x)
    x = _ensure_node(x)
    _is_constant(x) && return constant(1)  # A constant will always have one knot.
    return obtain_node((x,), CountKnots())
end

struct Merge2{T} <: NodeOp{T} end
create_evaluation_state(::Tuple{Node,Node}, ::Merge2) = EMPTY_NODE_STATE
function run_node!(
    ::Merge2{T},
    ::EmptyNodeEvaluationState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block,
    input_r::Block,
) where {T}
    # This is a very simplified version of Union alignment, since we do not need to keep
    # track of any previous values.

    # Fast-paths — any emptiness of inputs means that no merging is required.
    isempty(input_l) && return input_r
    isempty(input_r) && return input_l

    # Allocate a block of the maximum possible length. We'll trim it later.
    nl = length(input_l)
    nr = length(input_r)
    max_size = nl + nr
    times = _allocate_times(max_size)
    values = _allocate_values(T, max_size)

    # Store indices into the inputs. The index represents the next time point for
    # consideration for each series.
    il = 1
    ir = 1

    # Index into the output.
    j = 1

    # Loop until we exhaust inputs.
    # @inbounds while (il <= nl || ir <= nr)
    while (il <= nl || ir <= nr)
        # Store the next available time in the series, that is being pointed to by il & ir.
        next_time_l = il <= nl ? input_l.times[il] : DateTime(0)
        next_time_r = ir <= nr ? input_r.times[ir] : DateTime(0)

        time, value = if (il <= nl && next_time_l < next_time_r) || ir > nr
            # Left ticks next
            val = input_l.values[il]
            il += 1
            next_time_l, val
        elseif (ir <= nr && next_time_r < next_time_l) || il > nl
            # Right ticks next
            val = input_r.values[ir]
            ir += 1
            next_time_r, val
        else
            # A shared time point where neither left nor right have been exhausted.
            # Emit a value from the right-hand input in this case.
            val = input_r.values[ir]
            il += 1
            ir += 1
            next_time_r, val
        end

        # We always add a value
        times[j] = time
        values[j] = value
        j += 1
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(unchecked, times, values)
end

"""
    merge(x::Node...) -> Node

Given at least one node `x`, create a node that emits the union of knots from all `x`.

If one or more of the inputs contain knots at the same time, then only one will be emitted.
The _last_ input in which a knot occurs at a particular time will take precedence.

If the inputs `x` have different value types, then the resultant value type will be
promoted as necessary to accommodate all inputs.
"""
function Base.merge(x::Node, others::Node...)
    # This is an optimisation to ensure that if nodes are repeated in `others`, we only
    # keep the last instance of them.
    xs_backwards = unique(Iterators.reverse((x, others...)))
    x = last(xs_backwards)
    others = xs_backwards[(end - 1):-1:1]

    # Apply merging pairwise.
    return foldl(merge, others; init=x)
end
Base.merge(x::Node) = x
function Base.merge(x::Node, y::Node)
    x === y && return x
    T = promote_type(value_type(x), value_type(y))
    return obtain_node((x, y), Merge2{T}())
end
