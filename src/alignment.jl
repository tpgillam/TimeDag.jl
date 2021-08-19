"""Represent a technique for aligning two timeseries."""
abstract type Alignment end

"""For a pair (A, B), tick whenever A ticks so long as both nodes are active."""
struct LeftAlignment <: Alignment end

"""For a pair (A, B), tick whenever A or B ticks so long as both nodes are active."""
struct UnionAlignment <: Alignment end

"""For a pair (A, B), tick whenever A and B tick simultaneously."""
struct IntersectAlignment <: Alignment end

"""The default alignment for operators when not specified."""
const DEFAULT_ALIGNMENT = UnionAlignment

abstract type UnaryNodeOp{T, Stateful, AlwaysTicks} <: NodeOp{T} end
abstract type StatelessUnaryNodeOp{T, AlwaysTicks} <: UnaryNodeOp{T, false, AlwaysTicks} end
abstract type StatefulUnaryNodeOp{T, AlwaysTicks} <: UnaryNodeOp{T, true, AlwaysTicks} end

abstract type BinaryAlignedNodeOp{T, A <: Alignment} <: NodeOp{T} end

# TODO Some mechanism to describe whether the callable should be given the time of the knot
#   it is about to emit.
"""
    operator(::StatelessUnaryNodeOp{T, true}, x) -> value
    operator(::StatelessUnaryNodeOp{T, false}, x) -> (value, should_tick)
    operator(::StatefulUnaryNodeOp{T, true}, state, x) -> value
    operator(::StatefulUnaryNodeOp{T, false}, state, x) -> (value, should_tick)
    operator(::BinaryAlignedNodeOp, x, y) -> value

Perform the operation for this node.

For stateful operations, this operator should mutate the state as required.
For operations where `AlwaysTicks` type parameter is `false`, this should return a tuple
    of `(value, should_tick)`. If `should_tick` is `false`, we ignore `value` and do not
    emit a knot at this time.
"""
function operator end

_can_propagate_constant(::StatelessUnaryNodeOp{T, true}) where {T} = true
function _propagate_constant_value(
    op::StatelessUnaryNodeOp{T, true},
    parents::Tuple{Node}
) where {T}
    return operator(op, value(@inbounds(parents[1])))
end

_can_propagate_constant(::BinaryAlignedNodeOp{T}) where {T} = true
function _propagate_constant_value(
    op::BinaryAlignedNodeOp{T},
    parents::Tuple{Node, Node}
) where {T}
    return operator(op, map(value, parents)...)
end

function create_evaluation_state(::Tuple{Node}, ::StatelessUnaryNodeOp{T}) where {T}
    return _EMPTY_NODE_STATE
end

function run_node!(
    ::EmptyNodeEvaluationState,
    node_op::StatelessUnaryNodeOp{T, true},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{L},
) where {T, L}
    n = length(input)
    values = _allocate_values(T, n)
    for i in 1:n
        @inbounds values[i] = operator(node_op, input.values[i])
    end
    return Block(input.times, values)
end

function run_node!(
    ::EmptyNodeEvaluationState,
    node_op::StatelessUnaryNodeOp{T, false},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{L},
) where {T, L}
    n = length(input)
    times = _allocate_times(n)
    values = _allocate_values(T, n)
    j = 1
    for i in 1:n
        (value, should_tick) = operator(node_op, @inbounds(input.values[i]))
        if should_tick
            @inbounds times[j] = input.times[i]
            @inbounds values[j] = value
            j += 1
        end
    end
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(times, values)
end

function run_node!(
    state::NodeEvaluationState,
    node_op::StatefulUnaryNodeOp{T, true},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{L},
) where {T, L}
    n = length(input)
    values = _allocate_values(T, n)
    for i in 1:n
        @inbounds values[i] = operator(node_op, state, input.values[i])
    end
    return Block(input.times, values)
end

function run_node!(
    state::NodeEvaluationState,
    node_op::StatefulUnaryNodeOp{T, false},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{L},
) where {T, L}
    n = length(input)
    times = _allocate_times(n)
    values = _allocate_values(T, n)
    j = 1
    for i in 1:n
        (value, should_tick) = operator(node_op, state, @inbounds(input.values[i]))
        if should_tick
            @inbounds times[j] = input.times[i]
            @inbounds values[j] = value
            j += 1
        end
    end
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(times, values)
end

"""Apply, assuming `input_l` and `input_r` have identical alignment."""
function _apply_fast_align_binary(
    T,
    op::BinaryAlignedNodeOp,
    input_l::Block,
    input_r::Block,
)
    n = length(input_l)
    values = _allocate_values(T, n)
    # We shouldn't assume that it is valid to broadcast f over the inputs, so loop manually.
    for i in 1:n
        @inbounds values[i] = operator(op, input_l.values[i], input_r.values[i])
    end

    return Block(input_l.times, values)
end

# FIXME Add initial_values, and support for this.

# FIXME Instead of Nothing, use a custom marker type. Otherwise we need to make sure that
#   !(Nothing <: T).
#   Alternatively we could additionally store boolean sentinels to mark when each input is
#   active.

mutable struct UnionAlignmentState{L, R} <: NodeEvaluationState
    latest_l::Union{L, Nothing}
    latest_r::Union{R, Nothing}
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    ::BinaryAlignedNodeOp{T, UnionAlignment},
) where {T}
    return UnionAlignmentState{value_type(parents[1]), value_type(parents[2])}(
        nothing,
        nothing,
    )
end

function run_node!(
    state::UnionAlignmentState{L, R},
    node_op::BinaryAlignedNodeOp{T, UnionAlignment},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T, L, R}
    if isempty(input_l) && isempty(input_r)
        # Nothing to do, since neither input has ticked.
        return Block{T}()
    elseif isempty(input_l) && isnothing(state.latest_l)
        # Left is inactive and won't tick, so nothing gets emitted. But make sure we update
        # the state on the right.
        state.latest_r = @inbounds last(input_r.values)
        return Block{T}()
    elseif isempty(input_r) && isnothing(state.latest_r)
        # Right is inactive and won't tick, so nothing gets emitted. But make sure we update
        # the state on the left.
        state.latest_l = @inbounds last(input_l.values)
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable
        # Update the alignment state.
        state.latest_l = @inbounds last(input_l.values)
        state.latest_r = @inbounds last(input_r.values)
        return _apply_fast_align_binary(T, node_op, input_l, input_r)
    end

    # Create our outputs as the maximum possible size.
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

    # Store the next available time in the series, that is being pointed to by il & ir.
    next_time_l = DateTime(0)
    next_time_r = DateTime(0)

    # Loop until we exhaust inputs.
    while (il <= nl || ir <= nr)
        if (il <= nl)
            next_time_l = @inbounds input_l.times[il]
        end
        if (ir <= nr)
            next_time_r = @inbounds input_r.times[ir]
        end

        new_time = if (il <= nl && next_time_l < next_time_r) || ir > nr
            # Left ticks next
            state.latest_l = @inbounds input_l.values[il]
            il += 1
            next_time_l
        elseif (ir <= nr && next_time_r < next_time_l) || il > nl
            # Right ticks next
            state.latest_r = @inbounds input_r.values[ir]
            ir += 1
            next_time_r
        else
            # A shared time point where neither x1 nor x2 have been exhausted.
            state.latest_l = @inbounds input_l.values[il]
            state.latest_r = @inbounds input_r.values[ir]
            il += 1
            ir += 1
            next_time_l
        end

        # We must only output a knot if both inputs are active.
        if (isnothing(state.latest_l) || isnothing(state.latest_r))
            continue
        end

        # Output a knot.
        @inbounds times[j] = new_time
        @inbounds values[j] = operator(node_op, state.latest_l, state.latest_r)
        j += 1
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)

    return Block(times, values)
end

function create_evaluation_state(
    ::Tuple{Node, Node},
    ::BinaryAlignedNodeOp{T, IntersectAlignment},
) where {T}
    # Intersect alignment doesn't require remembering any previous state.
    return _EMPTY_NODE_STATE
end

function run_node!(
    ::EmptyNodeEvaluationState,
    node_op::BinaryAlignedNodeOp{T, IntersectAlignment},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T, L, R}
    if isempty(input_l) || isempty(input_r)
        # Output will be empty unless both inputs have ticked.
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable.
        return _apply_fast_align_binary(T, node_op, input_l, input_r)
    end

    # Create our outputs as the maximum possible size.
    nl = length(input_l)
    nr = length(input_r)
    max_size = nl
    times = _allocate_times(max_size)
    values = _allocate_values(T, max_size)

    # Store indices into the inputs. The index represents the next time point for
    # consideration for each series.
    il = 1
    ir = 1

    # Index into the output.
    j = 1

    # If we get to the end of either series, we know that we cannot add any more elements to
    # the output.
    while (il <= nl && ir <= nr)
        # Obtain the *next available* times from each entity. We know that the current
        # state, and last emitted, time is strictly less than either of these.
        time_l = @inbounds input_l.times[il]
        time_r = @inbounds input_r.times[ir]

        if time_l < time_r
            # Left ticks next; consider the next knot.
            il += 1
        elseif time_r < time_l
            # Right ticks next; consider the next knot.
            ir += 1
        else  # time_l == time_r
            # Shared time point, so emit a knot.
            @inbounds times[j] = time_l
            @inbounds values[j] = operator(node_op, input_l.values[il], input_r.values[ir])
            j += 1
            il += 1
            ir += 1
        end
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(times, values)
end

mutable struct LeftAlignmentState{R} <: NodeEvaluationState
    latest_r::Union{R, Nothing}
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    ::BinaryAlignedNodeOp{T, LeftAlignment},
) where {T}
    return LeftAlignmentState{value_type(parents[2])}(nothing)
end

function run_node!(
    state::LeftAlignmentState,
    node_op::BinaryAlignedNodeOp{T, LeftAlignment},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T, L, R}
    have_initial_r = !isnothing(state.latest_r)

    if isempty(input_l)
        # We will not tick, but update state if necessary.
        if !isempty(input_r)
            state.latest_r = @inbounds last(input_r.values)
        end
        return Block{T}()
    elseif isempty(input_r) && !have_initial_r
        # We cannot tick, since we have no values on the right. No state to update either.
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable.
        return _apply_fast_align_binary(T, node_op, input_l, input_r)
    end

    # The most we can emit is one knot for every knot in input_l.
    nl = length(input_l)
    nr = length(input_r)
    values = _allocate_values(T, nl)

    # Start with 0, indicating that input_r hasn't started ticking yet.
    ir = 0

    # The index of the first knot we emit from input_l. Note that if we have an initial
    # value for r, then we know it will be index 1. Otherwise use 0 as a placeholder to
    # indicate that we don't know.
    first_emitted_index_l = have_initial_r ? 1 : 0

    # The index into the output.
    j = 1

    for il in 1:nl
        # Consume r while it would leave us before the current time in l, or until we reach
        # the end of r.
        # TODO Check these conditions, add @inbounds when happy.
        # while (ir < nr && @inbounds(input_r.times[ir + 1] <= input_l.times[il]))
        while (ir < nr && input_r.times[ir + 1] <= input_l.times[il])
            ir += 1
        end

        if ir > 0
            if first_emitted_index_l == 0
                # Record the point where we have started ticking.
                first_emitted_index_l = il
            end
            @inbounds values[j] = operator(node_op, input_l.values[il], input_r.values[ir])
            j += 1
        elseif have_initial_r
            # R hasn't ticked in this batch, but we have an initial value. In this case
            # we know that `first_emitted_index_l` will have already been set correctly.
            @inbounds values[j] = operator(node_op, input_l.values[il], state.latest_r)
            j += 1
        end
    end

    # Update state
    if !isempty(input_r)
        state.latest_r = @inbounds last(input_r.values)
    end

    if (first_emitted_index_l == 0)
        # We expect this to happen when:
        #   * input_l ticks once at start of interval
        #   * input_r ticks several times after this
        # The output will be empty in this case.
        return Block{T}()
    end

    # Package results into a new block.
    times = if first_emitted_index_l > 1
        _trim!(values, j - 1)  # Truncate the values array, as we haven't used all of it.
        @view input_l.times[first_emitted_index_l:end]
    else
        input_l.times
    end

    return Block(times, values)
end