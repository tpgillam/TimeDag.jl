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

abstract type UnaryNodeOp{T} <: NodeOp{T} end
abstract type BinaryAlignedNodeOp{T, A <: Alignment} <: NodeOp{T} end

"""
    operator!(op::UnaryNodeOp{T}, (state,) out::Ref{T}, (time,) x) -> should_tick
    operator!(op::BinaryAlignedNodeOp{T}, (state,) out::Ref{T}, (time,) x, y) -> should_tick

Perform the operation for this node.

`state` should be omitted from the definition iff the node is stateless.
`time` should be omitted from the definition iff the node is time_agnostic.

For stateful operations, this operator should mutate the state as required.
If `should_tick` is `false`, we ignore the value placed into `ref_out`, and do not emit a
knot at this time.
"""
function operator! end

"""
    always_ticks(node) -> Bool
    always_ticks(op) -> Bool

Returns true iff the `should_tick` return value from `operator` can be assumed to always
be true.
"""
always_ticks(node::Node) = always_ticks(node.op)
always_ticks(::NodeOp) = false

"""
    stateless_operator(node) -> Bool
    stateless_operator(op) -> Bool

Returns true iff `operator(op, ...)` would never look at or modify the evaluation state.

If this returns true, `create_operator_evaluation_state` should return _EMPTY_NODE_STATE.

Note that if an `op` has `stateless(op)` returning true, then it necessarily should also
return true here. The default implementation is to return `stateless(op)`, meaning that if
one is creating a node that is fully stateless, one need only define `stateless`.
"""
stateless_operator(node::Node) = stateless_operator(node.op)
stateless_operator(op::NodeOp) = stateless(op)


"""
    create_operator_evaluation_state(parents, op::NodeOp) -> NodeEvaluationState

Create an empty evaluation state for the given node, when starting evaluation at the
specified time.

Note that this is state that will be passed to `operator`. The overall node may additionally
wrap this state with further state, if this is necessary for e.g. alignment.
"""
function create_operator_evaluation_state end

function operator!(
    op::NodeOp,
    state::NodeEvaluationState,
    out::Ref,
    time::DateTime,
    values...
)
    return if stateless_operator(op) && time_agnostic(op)
        operator!(op, out, values...)
    elseif stateless_operator(op) && !time_agnostic(op)
        operator!(op, out, time, values...)
    elseif !stateless_operator(op) && time_agnostic(op)
        operator!(op, state, out, values...)
    else
        error("Error! We should have dispatched to a more specialised method.")
    end
end

function _can_propagate_constant(op::UnaryNodeOp)
    return always_ticks(op) && stateless_operator(op) && time_agnostic(op)
end
function _propagate_constant_value(op::UnaryNodeOp{T}, parents::Tuple{Node}) where {T}
    out = Ref{T}()
    # NB, we know that time & state is ignored (due to _can_propagate_constant), therefore
    # we pass in garbage.
    # We also know that should_tick will end up being true, as the node always ticks.
    operator!(op, out, value(@inbounds(parents[1])))
    return @inbounds out[]
end

function _can_propagate_constant(op::BinaryAlignedNodeOp)
    always_ticks(op) && stateless_operator(op) && time_agnostic(op)
end
function _propagate_constant_value(
    op::BinaryAlignedNodeOp{T},
    parents::Tuple{Node, Node}
) where {T}
    out = Ref{T}()
    # NB, we know that time & state is ignored (due to _can_propagate_constant), therefore
    # we pass in garbage.
    # We also know that should_tick will end up being true, as the node always ticks.
    operator!(op, out, value(@inbounds(parents[1])), value(@inbounds(parents[2])))
    return @inbounds out[]
end


# An unary node has no alignment state, so any state comes purely from the operator.
function create_evaluation_state(parents::Tuple{Node}, op::UnaryNodeOp)
    return create_operator_evaluation_state(parents, op)
end

function run_node!(
    state::NodeEvaluationState,
    node_op::UnaryNodeOp{T},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{L},
) where {T, L}
    n = length(input)
    values = _allocate_values(T, n)
    return if always_ticks(node_op)
        # We can ignore the return value of the operator, since we have been promised that
        # it will always tick. Hence we can use a for loop too.
        for i in 1:n
            time = input.times[i]
            operator!(node_op, state, Ref(values, i), time, input.values[i])
        end
        Block(input.times, values)
    else
        times = _allocate_times(n)
        j = 1
        for i in 1:n
            time = input.times[i]
            should_tick = operator!(node_op, state, Ref(values, j), time, input.values[i])
            if should_tick
                @inbounds times[j] = input.times[i]
                j += 1
            end
        end
        _trim!(times, j - 1)
        _trim!(values, j - 1)
        Block(times, values)
    end
end

"""Apply, assuming `input_l` and `input_r` have identical alignment."""
function _apply_fast_align_binary!(
    T,
    op::BinaryAlignedNodeOp,
    operator_state::NodeEvaluationState,
    input_l::Block,
    input_r::Block,
)
    n = length(input_l)
    values = _allocate_values(T, n)
    return if always_ticks(node_op)
        # We shouldn't assume that it is valid to broadcast f over the inputs, so loop
        # manually.
        for i in 1:n
            time = input_l.times[i]
            operator!(
                op, operator_state, Ref(values, i),
                time, input_l.values[i], input_r.values[i]
            )
        end
        Block(input_l.times, values)
    else
        # FIXME Implement this branch!
        error("Not implemented!")
    end
end

# FIXME Add initial_values, and support for this.

# FIXME Instead of Nothing, use a custom marker type. Otherwise we need to make sure that
#   !(Nothing <: T).
#   Alternatively we could additionally store boolean sentinels to mark when each input is
#   active.

mutable struct UnionAlignmentState{L, R, OperatorState} <: NodeEvaluationState
    latest_l::Union{L, Nothing}
    latest_r::Union{R, Nothing}
    # TODO If OperatorState == EmptyNodeEvaluationState, it'd be nice not to store an extra
    # pointer here. Can we skip the field on the struct entirely? (Maybe just a different
    # struct is required.)
    operator_state::OperatorState
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    op::BinaryAlignedNodeOp{T, UnionAlignment},
) where {T}
    operator_state = create_operator_evaluation_state(parents, op)
    L = value_type(parents[1])
    R = value_type(parents[2])
    return UnionAlignmentState{L, R, typeof(operator_state)}(
        nothing,
        nothing,
        operator_state,
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
        return _apply_fast_align_binary!(T, node_op, state.operator_state, input_l, input_r)
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
        should_tick = operator!(
            node_op, state.operator_state, Ref(values, j),
            new_time, state.latest_l, state.latest_r
        )
        if always_ticks(node_op) || should_tick
            @inbounds times[j] = new_time
            j += 1
        end
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)

    return Block(times, values)
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    op::BinaryAlignedNodeOp{T, IntersectAlignment},
) where {T}
    # Intersect alignment doesn't require remembering any previous state, so just return
    # the operator state.
    return create_operator_evaluation_state(parents, op)
end

function run_node!(
    operator_state::NodeEvaluationState,
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
        return _apply_fast_align_binary!(T, node_op, operator_state, input_l, input_r)
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
            should_tick = operator!(
                node_op, operator_state, Ref(values, j),
                time_l, input_l.values[il], input_r.values[ir]
            )
            if always_ticks(node_op) || should_tick
                @inbounds times[j] = time_l
                j += 1
            end
            il += 1
            ir += 1
        end
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(times, values)
end

mutable struct LeftAlignmentState{R, OperatorState} <: NodeEvaluationState
    latest_r::Union{R, Nothing}
    # TODO As for UnionAlignmentState, would be nice to omit this field when not needed.
    operator_state::OperatorState
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    op::BinaryAlignedNodeOp{T, LeftAlignment},
) where {T}
    operator_state = create_operator_evaluation_state(parents, op)
    R = value_type(parents[2])
    return LeftAlignmentState{R, typeof(operator_state)}(nothing, operator_state)
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
        return _apply_fast_align_binary!(T, node_op, state.operator_state, input_l, input_r)
    end

    # The most we can emit is one knot for every knot in input_l.
    nl = length(input_l)
    nr = length(input_r)
    times = _allocate_times(nl)
    values = _allocate_values(T, nl)

    # Start with 0, indicating that input_r hasn't started ticking yet.
    ir = 0

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
            time = input_l.times[il]
            should_tick = operator!(
                node_op, state.operator_state, Ref(values, j),
                time, input_l.values[il], input_r.values[ir]
            )
            if always_ticks(node_op) || should_tick
                @inbounds times[j] = time
                j += 1
            end

        elseif have_initial_r
            # R hasn't ticked in this batch, but we have an initial value.
            time = input_l.times[il]
            should_tick = operator!(
                node_op, state.operator_state, Ref(values, j),
                time, input_l.values[il], state.latest_r
            )
            if always_ticks(node_op) || should_tick
                @inbounds times[j] = time
                j += 1
            end
        end
    end

    # Update state
    if !isempty(input_r)
        state.latest_r = @inbounds last(input_r.values)
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(times, values)
end
