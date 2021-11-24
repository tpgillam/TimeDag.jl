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
has_initial_values(::NaryNodeOp) = false

"""
    initial_left(op::BinaryNodeOp) -> L

Specify the initial value to use for the first parent of the given `op`.

Needs to be defined if [`has_initial_values`](@ref) returns true, and alignment is
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

"""
    initial_values(op::NaryNodeOp) -> Tuple

Specify the initial values to use for all parents of the given `op`.

Needs to be defined for nary ops for which [`has_initial_values`](@ref) returns true.
"""
function initial_values end

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

function _can_propagate_constant(op::Union{UnaryNodeOp,BinaryNodeOp,NaryNodeOp})
    return always_ticks(op) && stateless_operator(op) && time_agnostic(op)
end
function _propagate_constant_value(op::UnaryNodeOp, parents::Tuple{Node})
    # NB, we know that time & state is ignored (due to _can_propagate_constant).
    return operator!(op, value(@inbounds(parents[1])))
end
function _propagate_constant_value(op::BinaryNodeOp, parents::Tuple{Node,Node})
    return operator!(op, value(@inbounds(parents[1])), value(@inbounds(parents[2])))
end
function _propagate_constant_value(op::NaryNodeOp{N}, parents::NTuple{N,Node}) where {N}
    return operator!(op, map(value, parents)...)
end

"""
    _create_operator_evaluation_state(parents, op) -> NodeEvaluationState

Internal function that will look at `stateless_operator`, and iff it is false call
`create_operator_evaluation_state`. Otherwise return an empty node state.
"""
function _create_operator_evaluation_state(parents, op)
    return if stateless_operator(op)
        EMPTY_NODE_STATE
    else
        create_operator_evaluation_state(parents, op)
    end
end

# An unary node has no alignment state, so any state comes purely from the operator.
function create_evaluation_state(parents::Tuple{Node}, op::UnaryNodeOp)
    return _create_operator_evaluation_state(parents, op)
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
        @inbounds for i in 1:n
            time = input.times[i]
            values[i] = _operator!(node_op, state, time, input.values[i])
        end
        Block(unchecked, input.times, values)
    else
        times = _allocate_times(n)
        j = 1
        @inbounds for i in 1:n
            time = input.times[i]
            out = _operator!(node_op, state, time, input.values[i])
            if valid(out)
                values[j] = unsafe_value(out)
                times[j] = input.times[i]
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
        @inbounds for i in 1:n
            time = input_l.times[i]
            values[i] = _operator!(
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

operator_state(state::UnionWithOpState) = state.operator_state
operator_state(::UnionWithoutOpState) = EMPTY_NODE_STATE

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

    return if always_ticks(node_op)
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
    state::UnionAlignmentState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block,
    input_r::Block,
) where {T}
    @inbounds if isempty(input_l) && isempty(input_r)
        # Nothing to do, since neither input has ticked.
        return Block{T}()
    elseif isempty(input_l) && !state.valid_l
        # Left is inactive and won't tick, so nothing gets emitted. But make sure we update
        # the state on the right.
        _set_r!(state, last(input_r.values))
        return Block{T}()
    elseif isempty(input_r) && !state.valid_r
        # Right is inactive and won't tick, so nothing gets emitted. But make sure we update
        # the state on the left.
        _set_l!(state, last(input_l.values))
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

    # Loop until we exhaust inputs.
    @inbounds while (il <= nl || ir <= nr)
        # Store the next available time in the series, that is being pointed to by il & ir.
        next_time_l = il <= nl ? input_l.times[il] : DateTime(0)
        next_time_r = ir <= nr ? input_r.times[ir] : DateTime(0)

        new_time = if (il <= nl && next_time_l < next_time_r) || ir > nr
            # Left ticks next
            _set_l!(state, input_l.values[il])
            il += 1
            next_time_l
        elseif (ir <= nr && next_time_r < next_time_l) || il > nl
            # Right ticks next
            _set_r!(state, input_r.values[ir])
            ir += 1
            next_time_r
        else
            # A shared time point where neither x1 nor x2 have been exhausted.
            _set_l!(state, input_l.values[il])
            _set_r!(state, input_r.values[ir])
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
    return _create_operator_evaluation_state(parents, op)
end

function run_node!(
    node_op::BinaryNodeOp{T,IntersectAlignment},
    operator_state::NodeEvaluationState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block,
    input_r::Block,
) where {T}
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
    max_size = min(nl, nr)
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
    @inbounds while (il <= nl && ir <= nr)
        # Obtain the *next available* times from each entity. We know that the current
        # state, and last emitted, time is strictly less than either of these.
        next_time_l = input_l.times[il]
        next_time_r = input_r.times[ir]

        if next_time_l < next_time_r
            # Left ticks next; consider the next knot.
            il += 1
        elseif next_time_r < next_time_l
            # Right ticks next; consider the next knot.
            ir += 1
        else  # next_time_l == next_time_r
            # Shared time point, so emit a knot.
            j = _maybe_add_knot!(
                node_op,
                operator_state,
                times,
                values,
                j,
                next_time_l,
                input_l.values[il],
                input_r.values[ir],
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
    input_l::Block,
    input_r::Block,
) where {T}
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

    @inbounds for il in 1:nl
        # Consume r while it would leave us before the current time in l, or until we reach
        # the end of r.
        next_time_l = input_l.times[il]
        while (ir < nr && input_r.times[ir + 1] <= next_time_l)
            ir += 1
        end

        if ir > 0
            j = _maybe_add_knot!(
                node_op,
                operator_state(state),
                times,
                values,
                j,
                next_time_l,
                input_l.values[il],
                input_r.values[ir],
            )

        elseif have_initial_r
            # R hasn't ticked in this batch, but we have an initial value.
            j = _maybe_add_knot!(
                node_op,
                operator_state(state),
                times,
                values,
                j,
                next_time_l,
                input_l.values[il],
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

# Some thought went into how to store `latest` for the nary case.
#
# Ideally one would use a mutable heterogeneous collection (i.e. a "mutable tuple"), but
# such a thing doesn't exist in Julia. There are tricks one can use if your elements are
# isbits (see StaticArrays.MArray), but we want a solution that can work for *any* input
# Julia type.
#
# Options considered:
#   1. Nary alignment, with latest::Vector{Any} and accept that state *cannot* store latest
#       values efficiently (will be a lot of runtime type checking). This WILL be slow, as
#       it is in the inner loop of evaluation.
#   2. Nary alignment, and use a Tuple for storage.
#       But, because this isn't mutable, will have to use `Base.setindex` to update, which
#       could theoretically do a lot of allocating.
#   3. Use code generation to make Union2, Union3, Union4, ...
#       This bloats the code somewhat, but would be guaranteed to be fast.
#       However, there is then an arbitrary limit to the number of things that we can align.
#
# Benchmarking suggests that option 2 can actually be quite efficient in practice, since if
# we immediately assign the tuple, LLVM has the ability to re-use memory. We hence take this
# approach.
#
# In the future, we could generate a SMALL number of additional special-cases using option 3
# (if, for example, we found ourselves doing a lot of ternary alignment).
#
# Also, to simplify matters, we use a single alignment state. It is slightly less memory
# efficient, but should result in less code generation.

# `Types` will look something like Tuple{In1,In2,...}
mutable struct NaryAlignmentState{N,Types<:Tuple,OperatorState} <: NodeEvaluationState
    # Since we may not have a latest value, we use the partial initialisation trick inside
    # `Maybe` to avoid having to invent an unused placeholder.
    latest::Tuple{Vararg{Maybe}}
    operator_state::OperatorState

    function NaryAlignmentState{N,Types}(
        operator_state::OperatorState
    ) where {N,Types,OperatorState}
        return new{N,Types,OperatorState}(
            Tuple(Maybe{T}() for T in Types.parameters), operator_state
        )
    end

    function NaryAlignmentState{N,Types}(
        operator_state::OperatorState, initial_values::Types
    ) where {N,Types,OperatorState}
        return new{N,Types,OperatorState}(
            Tuple(Maybe(v) for v in initial_values), operator_state
        )
    end
end

operator_state(state::NaryAlignmentState) = state.operator_state

Base.@propagate_inbounds function _set!(state::NaryAlignmentState, x, i::Integer)
    # TODO Consider making a mutable Maybe type, to avoid possible reconstruction of the
    #   tuple? It might just end up being slower though due to extra dereferencing.
    # The state tuple is not mutable, so we need to use this trick.
    state.latest = Base.setindex(state.latest, Maybe(x), i)
    return state
end

function create_evaluation_state(parents::NTuple{N,Node}, op::NaryNodeOp{N}) where {N}
    # Work out the tuple of input types necessary for constructing the alignment state.
    Types = Tuple{map(value_type, parents)...}
    operator_state = _create_operator_evaluation_state(parents, op)

    return if has_initial_values(op)
        NaryAlignmentState{N,Types}(operator_state, initial_values(op))
    else
        NaryAlignmentState{N,Types}(operator_state)
    end
end

function create_evaluation_state(
    parents::NTuple{N,Node}, op::NaryNodeOp{N,T,IntersectAlignment}
) where {N,T}
    # Intersect alignment doesn't require remembering any previous state, so just return
    # the operator state.
    return _create_operator_evaluation_state(parents, op)
end

"""Apply, assuming all `inputs` have identical alignment."""
function _apply_fast_align_nary!(
    op::NaryNodeOp{N,T}, operator_state::NodeEvaluationState, inputs::NTuple{N,Block}
) where {N,T}
    times = @inbounds first(inputs).times
    n = length(times)
    values = _allocate_values(T, n)
    return if always_ticks(op)
        @inbounds for i in 1:n
            time = times[i]
            values[i] = _operator!(
                op, operator_state, time, map(x -> x.values[i], inputs)...
            )
        end
        Block(unchecked, times, values)
    else
        # FIXME Implement this branch!
        error("Not implemented!")
    end
end

"""
    equivalence_classes(f, collection) -> Vector{Vector{eltype(collection)}}

Generate the set of equivalence classes for `collection` generated by the equivalence
relation `f : T × T → Bool`.

Note that behaviour is undefined if `f` is non-transitive.
"""
function equivalence_classes(
    f::Function, x::Union{AbstractVector{T},Tuple{Vararg{T}}}
) where {T}
    result = Vector{Vector{T}}()
    isempty(x) && return result

    @inbounds for el in x
        for class in result
            f(el, first(class)) || continue
            push!(class, el)
            # Jump to "found" label below. This means that we don't need to add a new
            # equivalence class.
            @goto found
        end

        # We end up here if we didn't find an existing equivalence class for `el`, so we
        # need to create a new one.
        push!(result, T[el])

        # Label used for escaping from the for loop above.
        @label found
    end
    return result
end

function run_node!(
    node_op::NaryNodeOp{N,T,UnionAlignment},
    state::NaryAlignmentState{N},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    inputs::Block...,
) where {N,T}
    @assert N == length(inputs)

    inputs_empty = map(isempty, inputs)
    @inbounds if all(inputs_empty)
        # Nothing to do, as no inputs have ticked.
        return Block{T}()
    elseif any(inputs_empty .& map(!valid, state.latest))
        # There is at least one input which has an empty input and does *not* have an
        # initial value.

        # We need to make sure we update any states which do have inputs.
        for (i, input) in enumerate(inputs)
            isempty(input) && continue
            _set!(state, last(input.values), i)
        end

        # The output will, however, be empty.
        return Block{T}()
    end

    input_classes = equivalence_classes(_equal_times, inputs)

    if length(input_classes) == 1
        # All times are indistinguishable.
        # Update alignment state and use fast alignment.
        @inbounds for (k, input) in enumerate(inputs)
            _set!(state, last(input.values), k)
        end
        return _apply_fast_align_nary!(node_op, operator_state(state), inputs)
    end

    # TODO `max_size` could be a massive overestimate.
    #   In practice it may be better to pick something smaller, and then increase the buffer
    #   size where necessary.

    # We use an optimisation here, whereby we use the `_equal_times` equivalence
    # relation to partition the inputs into sets which have equal times. We know that times
    # that are equal can only appear once, so this avoids some double counting.
    max_size = sum(x -> length(first(x)), input_classes)
    times = _allocate_times(max_size)
    values = _allocate_values(T, max_size)

    # Indices into the inputs. The index represents the next time point for
    # consideration for each series.
    is = MVector{N,Int64}(ones(N))

    # Index into the output.
    j = 1

    ns = map(length, inputs)
    @inbounds while true
        unfinisheds = (is .<= ns)
        any(unfinisheds) || break  # Loop until we exhaust inputs.

        # For each input, figure out the next time it would tick.
        next_times = ntuple(Val(N)) do k
            # If we're at the end of the series, just use a placeholder.
            !unfinisheds[k] && return typemax(DateTime)
            return inputs[k].times[is[k]]
        end

        # This is when we will next tick.
        new_time = minimum(next_times)

        # For every input that ticks at exactly this time, update to use the new value.
        for k in 1:N
            unfinisheds[k] || continue
            next_times[k] == new_time || continue
            # If we are here, this input should advance.
            _set!(state, inputs[k].values[is[k]], k)
            is[k] += 1
        end

        # We must only output a knot if all inputs are active.
        all(map(valid, state.latest)) || continue

        # Compute and possibly output a knot.
        j = _maybe_add_knot!(
            node_op,
            operator_state(state),
            times,
            values,
            j,
            new_time,
            map(unsafe_value, state.latest)...,
        )
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)

    return Block(unchecked, times, values)
end

function run_node!(
    node_op::NaryNodeOp{N,T,IntersectAlignment},
    operator_state::NodeEvaluationState,
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    inputs::Block...,
) where {N,T}
    @assert N == length(inputs)

    if any(isempty, inputs)
        # Nothing to do, as no inputs have ticked.
        return Block{T}()
    end

    input_classes = equivalence_classes(_equal_times, inputs)

    if length(input_classes) == 1
        # All times are indistinguishable, so use fast alignment.
        return _apply_fast_align_nary!(node_op, operator_state, inputs)
    end

    # Create our output as the maximum possible size.
    ns = map(length, inputs)
    max_size = minimum(ns)
    times = _allocate_times(max_size)
    values = _allocate_values(T, max_size)

    # Store indices into the inputs. The index represents the next time point for
    # consideration for each series.
    is = MVector{N,Int64}(ones(N))

    # Index into the output.
    j = 1

    # If we get to the end of any series, we know that we cannot add any more elements to
    # the output.
    @inbounds while all(is .<= ns)
        # For each input, figure out the next time it would tick.
        next_times = ntuple(k -> inputs[k].times[is[k]], Val(N))

        # This is when we *might* next tick, if all inputs tick at this time.
        new_time = minimum(next_times)

        tick_mask = next_times .== new_time
        if all(tick_mask)
            # All inputs tick simultaneously, this means we should compute and possibly
            # output a knot.
            input_values = map(zip(is, inputs)) do pair
                i, input = pair
                return input.values[i]
            end
            j = _maybe_add_knot!(
                node_op, operator_state, times, values, j, new_time, input_values...
            )
            # Advance all pointers.
            is .+= 1
        else
            # We aren't going to emit a knot, so advance all inputs that tick next.
            for k in 1:N
                next_times[k] == new_time || continue
                # If we are here, this input should advance.
                is[k] += 1
            end
        end
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    _trim!(times, j - 1)
    _trim!(values, j - 1)
    return Block(unchecked, times, values)
end
