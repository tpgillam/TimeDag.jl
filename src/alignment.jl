"""Represent a technique for aligning two timeseries."""
abstract type Alignment end
struct LeftAlignment <: Alignment end
struct UnionAlignment <: Alignment end
struct IntersectAlignment <: Alignment end

"""
    LEFT

For inputs `(A, B, ...)`, tick whenever `A` ticks so long as all inputs are active.
"""
const LEFT = LeftAlignment()

"""
    UNION

For inputs `(A, B, ...)`, tick whenever any input ticks so long as all inputs are active.
"""
const UNION = UnionAlignment()

"""
    INTERSECT

For inputs `(A, B, ...)`, tick whenever all inputs tick simultaneously.
"""
const INTERSECT = IntersectAlignment()

"""The default alignment for operators when not specified."""
const DEFAULT_ALIGNMENT = UNION

"""
    UnaryNodeOp{T} <: NodeOp{T}

An abstract type representing a node op with a single parent.
"""
abstract type UnaryNodeOp{T} <: NodeOp{T} end

"""
    BinaryNodeOp{T,A<:Alignment} <: NodeOp{T}

An abstract type representing a node op with two parents, and using alignment `A`.
"""
abstract type BinaryNodeOp{T,A<:Alignment} <: NodeOp{T} end

"""
    NaryNodeOp{N,T,A<:Alignment} <: NodeOp{T}

An abstract type representing a node op with `N` parents, and using alignment `A`.

This type should be avoided for `N < 3`, since in these cases it would be more appropriate
to use either [`TimeDag.UnaryNodeOp`](@ref) or [`TimeDag.BinaryNodeOp`](@ref).
"""
abstract type NaryNodeOp{N,T,A<:Alignment} <: NodeOp{T} end

# A note on the design choice here, which is motivated by performance reasons & profiling.
#
# Options considered:
#   1. Return `(value::T, should_tick::Bool)` pair always
#   2. Take `out::Ref{T}` as a parameter, return `should_tick::Bool`
#   3. Return `Maybe{T}`.
#
# Option 1 was disfavoured, because if `should_tick` is false, one still needs to invent a
#   `value` of type `T`, which is possibly hard in general.
# Option 2 was found, from benchmarking, to be moderately slower than the other choices.
#
# Option 3 was found to retain the performance of option 1 with minimal overhead.
#
# For cases when we know the node will always tick (as indicated by `always_ticks(op)`) we
# just return a raw `T`, as the extra information will not be used.
"""
    operator!(op::UnaryNodeOp{T}, (state,), (time,) x) -> T / Maybe{T}
    operator!(op::BinaryNodeOp{T}, (state,), (time,) x, y) -> T / Maybe{T}
    operator!(op::NaryNodeOp{N,T}, (state,), (time,) x, y, ...) -> T / Maybe{T}

Perform the operation for this node.

When defining a method of this for a new op, follow these rules:
- `state` should be omitted iff [`TimeDag.stateless_operator`](@ref).
- `time` should be omitted iff [`TimeDag.time_agnostic`](@ref).
- All values `x, y, ...` should be omittted iff [`TimeDag.value_agnostic`](@ref).

For stateful operations, this operator should mutate `state` as required.

The return value `out` should be of type `T` iff [`TimeDag.always_ticks`](@ref) is true,
otherwise it should be of type [`TimeDag.Maybe`](@ref).

If `out <: Maybe{T}`, and has `!valid(out)`, this indicates that we do not wish to emit a
knot at this time, and it will be skipped. Otherwise, `value(out)` will be used as the
output value.
"""
function operator! end

"""
    always_ticks(node) -> Bool
    always_ticks(op) -> Bool

Returns true iff the return value from `operator` can be assumed to always be valid.

Note, that for sensible performance characteristics, this should be knowable from
`typeof(op)`
"""
always_ticks(node::Node) = always_ticks(node.op)
always_ticks(::NodeOp) = false

"""
    stateless_operator(node) -> Bool
    stateless_operator(op) -> Bool

Returns true iff `operator(op, ...)` would never look at or modify the evaluation state.

If this returns true, `create_operator_evaluation_state` will not be used.

Note that if an `op` has `stateless(op)` returning true, then it necessarily should also
return true here. The default implementation is to return `stateless(op)`, meaning that if
one is creating a node that is fully stateless, one need only define `stateless`.
"""
stateless_operator(node::Node) = stateless_operator(node.op)
stateless_operator(op::NodeOp) = stateless(op)

"""
    time_agnostic(node) -> Bool
    time_agnostic(op) -> Bool

Returns true iff `op` does not care about the time of the input knot(s).
"""
time_agnostic(node::Node) = time_agnostic(node.op)
time_agnostic(::NodeOp) = false

"""
    value_agnostic(node) -> Bool
    value_agnostic(op) -> Bool

Returns true iff `op` does not care about the value(s) of the input knot(s).
"""
value_agnostic(node::Node) = value_agnostic(node.op)
value_agnostic(::NodeOp) = false

"""
    create_operator_evaluation_state(parents, op::NodeOp) -> NodeEvaluationState

Create an empty evaluation state for the given node, when starting evaluation at the
specified time.

Note that this is state that will be passed to `operator`. The overall node may additionally
wrap this state with further state, if this is necessary for e.g. alignment.
"""
function create_operator_evaluation_state end

"""
    has_initial_values(op) -> Bool

If this returns true, it indicates that initial values for the `op`'s parents are specified.

See the documentation on [Initial values](@ref) for further information.
"""
has_initial_values(::BinaryNodeOp) = false

"""
    initial_left(op::BinaryNodeOp) -> L

Specify the initial value to use for the first parent of the given `op`.

Needs to be defined if `has_initial_values(op)` returns true, and alignment is
[`UNION`](@ref). For other alignments it is not required.
"""
function initial_left end

"""
    initial_right(op::BinaryNodeOp) -> R

Specify the initial value to use for the second parent of the given `op`.

Needs to be defined if `has_initial_values(op)` returns true, and alignment is
[`UNION`](@ref) or [`LEFT`](@ref). For [`INTERSECT`](@ref) alignment it is not required.
"""
function initial_right end

"""Convenience method to dispatch to reduced-argument `operator!` calls."""
function _operator!(op::NodeOp, state::NodeEvaluationState, time::DateTime, values...)
    return if stateless_operator(op) && time_agnostic(op)
        value_agnostic(op) ? operator!(op) : operator!(op, values...)
    elseif stateless_operator(op) && !time_agnostic(op)
        value_agnostic(op) ? operator!(op, time) : operator!(op, time, values...)
    elseif !stateless_operator(op) && time_agnostic(op)
        value_agnostic(op) ? operator!(op, state) : operator!(op, state, values...)
    else
        error("Error! We should have dispatched to a more specialised method.")
    end
end

function _can_propagate_constant(op::UnaryNodeOp)
    return always_ticks(op) && stateless_operator(op) && time_agnostic(op)
end
function _propagate_constant_value(op::UnaryNodeOp, parents::Tuple{Node})
    # NB, we know that time & state is ignored (due to _can_propagate_constant).
    return operator!(op, value(@inbounds(parents[1])))
end

function _can_propagate_constant(op::BinaryNodeOp)
    return always_ticks(op) && stateless_operator(op) && time_agnostic(op)
end
function _propagate_constant_value(op::BinaryNodeOp, parents::Tuple{Node,Node})
    return operator!(op, value(@inbounds(parents[1])), value(@inbounds(parents[2])))
end

# An unary node has no alignment state, so any state comes purely from the operator.
function create_evaluation_state(parents::Tuple{Node}, op::UnaryNodeOp)
    return if stateless_operator(op)
        EMPTY_NODE_STATE
    else
        create_operator_evaluation_state(parents, op)
    end
end

function run_node!(
    node_op::UnaryNodeOp{T},
    state::NodeEvaluationState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{L},
) where {T,L}
    n = length(input)
    values = _allocate_values(T, n)
    return if always_ticks(node_op)
        # We can ignore the validity of the return value of the operator, since we have been
        # promised that it will always tick. Hence we can use a for loop too.
        for i in 1:n
            time = @inbounds input.times[i]
            @inbounds values[i] = _operator!(node_op, state, time, input.values[i])
        end
        Block(unchecked, input.times, values)
    else
        times = _allocate_times(n)
        j = 1
        for i in 1:n
            time = @inbounds input.times[i]
            out = _operator!(node_op, state, time, @inbounds(input.values[i]))
            if valid(out)
                @inbounds values[j] = unsafe_value(out)
                @inbounds times[j] = input.times[i]
                j += 1
            end
        end
        _trim!(times, j - 1)
        _trim!(values, j - 1)
        Block(unchecked, times, values)
    end
end

"""Apply, assuming `input_l` and `input_r` have identical alignment."""
function _apply_fast_align_binary!(
    op::BinaryNodeOp{T}, operator_state::NodeEvaluationState, input_l::Block, input_r::Block
) where {T}
    n = length(input_l)
    values = _allocate_values(T, n)
    return if always_ticks(op)
        # We shouldn't assume that it is valid to broadcast f over the inputs, so loop
        # manually.
        for i in 1:n
            time = @inbounds input_l.times[i]
            @inbounds values[i] = _operator!(
                op, operator_state, time, input_l.values[i], input_r.values[i]
            )
        end
        Block(unchecked, input_l.times, values)
    else
        # FIXME Implement this branch!
        error("Not implemented!")
    end
end

abstract type UnionAlignmentState{L,R} <: NodeEvaluationState end

mutable struct UnionWithOpState{L,R,OperatorState} <: UnionAlignmentState{L,R}
    valid_l::Bool
    valid_r::Bool
    operator_state::OperatorState
    # These fields may initially be uninitialised.
    latest_l::L
    latest_r::R

    function UnionWithOpState{L,R}(operator_state::OperatorState) where {L,R,OperatorState}
        return new{L,R,OperatorState}(false, false, operator_state)
    end

    function UnionWithOpState{L,R}(
        operator_state::OperatorState, initial_l::L, initial_r::R
    ) where {L,R,OperatorState}
        return new{L,R,OperatorState}(true, true, operator_state, initial_l, initial_r)
    end
end

mutable struct UnionWithoutOpState{L,R} <: UnionAlignmentState{L,R}
    valid_l::Bool
    valid_r::Bool
    # These fields may initially be uninitialised.
    latest_l::L
    latest_r::R

    function UnionWithoutOpState{L,R}() where {L,R}
        return new{L,R}(false, false)
    end

    function UnionWithoutOpState{L,R}(initial_l::L, initial_r::R) where {L,R}
        return new{L,R}(true, true, initial_l, initial_r)
    end
end

operator_state(::UnionWithoutOpState) = EMPTY_NODE_STATE
operator_state(state::UnionWithOpState) = state.operator_state

function _set_l!(state::UnionAlignmentState{L}, x::L) where {L}
    state.latest_l = x
    state.valid_l = true
    return state
end

function _set_r!(state::UnionAlignmentState{L,R}, x::R) where {L,R}
    state.latest_r = x
    state.valid_r = true
    return state
end

function create_evaluation_state(
    parents::Tuple{Node,Node}, op::BinaryNodeOp{T,UnionAlignment}
) where {T}
    L = value_type(parents[1])
    R = value_type(parents[2])
    return if stateless_operator(op)
        if has_initial_values(op)
            UnionWithoutOpState{L,R}(initial_left(op), initial_right(op))
        else
            UnionWithoutOpState{L,R}()
        end
    else
        operator_state = create_operator_evaluation_state(parents, op)
        if has_initial_values(op)
            UnionWithOpState{L,R}(operator_state, initial_left(op), initial_right(op))
        else
            UnionWithOpState{L,R}(operator_state)
        end
    end
end

@inline function _maybe_add_knot!(
    node_op::NodeOp,
    operator_state::NodeEvaluationState,
    out_times::AbstractVector{DateTime},
    out_values::AbstractVector{T},
    j::Int,
    time::DateTime,
    in_values...,
) where {T}
    # Find the output value. For a given op this will either be of type T, or Maybe{T}, and
    # we can (at compile time) select the correct branch below based on `always_ticks(op)`.
    out = _operator!(node_op, operator_state, time, in_values...)

    if always_ticks(node_op)
        # Output value is raw, and should always be used.
        @inbounds out_times[j] = time
        @inbounds out_values[j] = out
        j + 1
    else
        if valid(out)
            # Add the output only if the output is valid.
            @inbounds out_times[j] = time
            @inbounds out_values[j] = unsafe_value(out)
            j + 1
        else
            j
        end
    end
end

function run_node!(
    node_op::BinaryNodeOp{T,UnionAlignment},
    state::UnionAlignmentState{L,R},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T,L,R}
    if isempty(input_l) && isempty(input_r)
        # Nothing to do, since neither input has ticked.
        return Block{T}()
    elseif isempty(input_l) && !state.valid_l
        # Left is inactive and won't tick, so nothing gets emitted. But make sure we update
        # the state on the right.
        _set_r!(state, @inbounds last(input_r.values))
        return Block{T}()
    elseif isempty(input_r) && !state.valid_r
        # Right is inactive and won't tick, so nothing gets emitted. But make sure we update
        # the state on the left.
        _set_l!(state, @inbounds last(input_l.values))
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable
        # Update the alignment state.
        _set_l!(state, @inbounds last(input_l.values))
        _set_r!(state, @inbounds last(input_r.values))
        return _apply_fast_align_binary!(node_op, operator_state(state), input_l, input_r)
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
            _set_l!(state, @inbounds input_l.values[il])
            il += 1
            next_time_l
        elseif (ir <= nr && next_time_r < next_time_l) || il > nl
            # Right ticks next
            _set_r!(state, @inbounds input_r.values[ir])
            ir += 1
            next_time_r
        else
            # A shared time point where neither x1 nor x2 have been exhausted.
            _set_l!(state, @inbounds input_l.values[il])
            _set_r!(state, @inbounds input_r.values[ir])
            il += 1
            ir += 1
            next_time_l
        end

        # We must only output a knot if both inputs are active.
        if !state.valid_l || !state.valid_r
            continue
        end

        # Compute and possibly output a knot.
        j = _maybe_add_knot!(
            node_op,
            operator_state(state),
            times,
            values,
            j,
            new_time,
            state.latest_l,
            state.latest_r,
        )
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)

    return Block(unchecked, times, values)
end

function create_evaluation_state(
    parents::Tuple{Node,Node}, op::BinaryNodeOp{T,IntersectAlignment}
) where {T}
    # Intersect alignment doesn't require remembering any previous state, so just return
    # the operator state.
    return if stateless_operator(op)
        EMPTY_NODE_STATE
    else
        create_operator_evaluation_state(parents, op)
    end
end

function run_node!(
    node_op::BinaryNodeOp{T,IntersectAlignment},
    operator_state::NodeEvaluationState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T,L,R}
    if isempty(input_l) || isempty(input_r)
        # Output will be empty unless both inputs have ticked.
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable.
        return _apply_fast_align_binary!(node_op, operator_state, input_l, input_r)
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
            j = _maybe_add_knot!(
                node_op,
                operator_state,
                times,
                values,
                j,
                time_l,
                @inbounds(input_l.values[il]),
                @inbounds(input_r.values[ir])
            )
            il += 1
            ir += 1
        end
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(unchecked, times, values)
end

abstract type LeftAlignmentState{R} <: NodeEvaluationState end

mutable struct LeftWithOpState{R,OperatorState} <: LeftAlignmentState{R}
    valid_r::Bool
    operator_state::OperatorState
    latest_r::R

    function LeftWithOpState{R}(operator_state::OperatorState) where {R,OperatorState}
        return new{R,OperatorState}(false, operator_state)
    end

    function LeftWithOpState{R}(
        operator_state::OperatorState, initial_r::R
    ) where {R,OperatorState}
        return new{R,OperatorState}(true, operator_state, initial_r)
    end
end

mutable struct LeftWithoutOpState{R} <: LeftAlignmentState{R}
    valid_r::Bool
    latest_r::R

    LeftWithoutOpState{R}() where {R} = new{R}(false)
    LeftWithoutOpState{R}(initial_r::R) where {R} = new{R}(true, initial_r)
end

operator_state(::LeftWithoutOpState) = EMPTY_NODE_STATE
operator_state(state::LeftWithOpState) = state.operator_state

function _set_r!(state::LeftAlignmentState{R}, x::R) where {R}
    state.latest_r = x
    state.valid_r = true
    return state
end

function create_evaluation_state(
    parents::Tuple{Node,Node}, op::BinaryNodeOp{T,LeftAlignment}
) where {T}
    R = value_type(parents[2])
    return if stateless_operator(op)
        if has_initial_values(op)
            LeftWithoutOpState{R}(initial_right(op))
        else
            LeftWithoutOpState{R}()
        end
    else
        operator_state = create_operator_evaluation_state(parents, op)
        if has_initial_values(op)
            LeftWithOpState{R}(operator_state, initial_right(op))
        else
            LeftWithOpState{R}(operator_state)
        end
    end
end

function run_node!(
    node_op::BinaryNodeOp{T,LeftAlignment},
    state::LeftAlignmentState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T,L,R}
    have_initial_r = state.valid_r

    if isempty(input_l)
        # We will not tick, but update state if necessary.
        if !isempty(input_r)
            _set_r!(state, @inbounds last(input_r.values))
        end
        return Block{T}()
    elseif isempty(input_r) && !have_initial_r
        # We cannot tick, since we have no values on the right. No state to update either.
        return Block{T}()
    end

    if _equal_times(input_l, input_r)
        # Times are indistinguishable.
        return _apply_fast_align_binary!(node_op, operator_state(state), input_l, input_r)
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
        while (ir < nr && @inbounds(input_r.times[ir + 1] <= input_l.times[il]))
            ir += 1
        end

        if ir > 0
            time = @inbounds input_l.times[il]

            j = _maybe_add_knot!(
                node_op,
                operator_state(state),
                times,
                values,
                j,
                time,
                @inbounds(input_l.values[il]),
                @inbounds(input_r.values[ir])
            )

        elseif have_initial_r
            # R hasn't ticked in this batch, but we have an initial value.
            time = @inbounds input_l.times[il]

            j = _maybe_add_knot!(
                node_op,
                operator_state(state),
                times,
                values,
                j,
                time,
                @inbounds(input_l.values[il]),
                state.latest_r,
            )
        end
    end

    # Update state
    if !isempty(input_r)
        _set_r!(state, @inbounds last(input_r.values))
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(unchecked, times, values)
end
