"""Represent a technique for aligning two timeseries."""
abstract type Alignment end

"""For a pair (A, B), tick whenever A ticks so long as both nodes are active."""
struct LeftAlignment <: Alignment end

"""For a pair (A, B), tick whenever A or B ticks so long as both nodes are active."""
struct UnionAlignment <: Alignment end

"""For a pair (A, B), tick whenever A and B tick simultaneously."""
struct IntersectAlignment <: Alignment end

"""The default alignment for operators when not specified."""
const DEFAULT_ALIGNMENT = UnionAlignment()


# TODO There should be optimisations for constant nodes somewhere.
#   How should constant nodes work? Presumably some subtype of a NodeOp?


abstract type BinaryAlignedNodeOp{T, A <: Alignment} <: NodeOp{T} end

"""
    binary_operator(::BinaryAlignedNodeOp) -> callable

Get the binary operator that should be used for this node.
"""
function binary_operator end

# FIXME Add initial_values, and support for this.

# TODO This should be refactored, as it will be shared for all binary nodes.

# FIXME Instead of Nothing, use a custom marker type. Otherwise we need to make sure that
#   !(Nothing <: T).
#   Alternatively we could additionally store boolean sentinels to mark when each input is
#   active.

mutable struct BinaryAlignmentState{L, R} <: NodeEvaluationState
    latest_l::Union{L, Nothing}
    latest_r::Union{R, Nothing}
end

function create_evaluation_state(
    parents::Tuple{Node, Node},
    ::BinaryAlignedNodeOp{T, A},
) where {T, A <: Alignment}
    return BinaryAlignmentState{value_type(parents[1]), value_type(parents[2])}(
        nothing,
        nothing,
    )
end

function create_evaluation_state(
    ::Tuple{Node, Node},
    ::BinaryAlignedNodeOp{T, IntersectAlignment},
) where {T}
    # Intersect alignment doesn't require remembering any previous state.
    return _EMPTY_NODE_STATE
end

function _equal_times(a::Block, b::Block)::Bool
    # FIXME This doesn't account for the case where e.g. a.times is a vector, and b.times is
    #   a view of the entirety of a.times.
    return a.times === b.times
end

"""Apply, assuming `input_l` and `input_r` have identical alignment."""
function _apply_fast_align_binary(T, f, input_l::Block, input_r::Block)
    n = length(input_l)
    values = _allocate_values(T, n)
    # We shouldn't assume that it is valid to broadcast f over the inputs, so loop manually.
    for i in 1:n
        @inbounds values[i] = f(input_l.values[i], input_r.values[i])
    end

    return Block(input_l.times, values)
end

function run_node!(
    state::BinaryAlignmentState{L, R},
    node_op::BinaryAlignedNodeOp{T, UnionAlignment},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input_l::Block{L},
    input_r::Block{R},
) where {T, L, R}
    if isempty(input_l) && isempty(input_r)
        # Nothing to do, since neither input has ticked.
        return Block{T}()
    elseif isempty(input_l) && isnothing(state.latest_r)
        # We won't emit any knots, but should update the state.
        state.latest_r = last(input_r.values)
        return Block{T}()
    elseif isnothing(state.latest_l) && isempty(input_l)
        state.latest_l = last(input_l.values)
        return Block{T}()
    end

    # This is the binary operator that we will be applying to input values.
    f = binary_operator(node_op)

    if _equal_times(input_l, input_r)
        # Times are indistinguishable
        # Update the alignment state.
        state.latest_l = last(input_l.values)
        state.latest_r = last(input_r.values)
        return _apply_fast_align_binary(T, f, input_l, input_r)
    end

    # Create our outputs as the maximum possible size.
    nl = length(input_l)
    nr = length(input_r)
    max_size = nl + nr
    times = Vector{DateTime}(undef, max_size)
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
        @inbounds values[j] = f(state.latest_l, state.latest_r)
        j += 1
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    # TODO It sounds like this currently doesn't actually free any of the buffer, which
    #   could be a bit inefficient. Maybe sizehint! is required too?
    resize!(times, j - 1)
    resize!(values, j - 1)

    return Block(times, values)
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

    # This is the binary operator that we will be applying to input values.
    f = binary_operator(node_op)

    if _equal_times(input_l, input_r)
        # Times are indistinguishable.
        return _apply_fast_align_binary(T, f, input_l, input_r)
    end

    # Create our outputs as the maximum possible size.
    nl = length(input_l)
    nr = length(input_r)
    max_size = max(nl, nr)
    times = Vector{DateTime}(undef, max_size)
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
            @inbounds values[j] = f(input_l.values[il], input_r.values[ir])
            j += 1
            il += 1
            ir += 1
        end
    end

    # Package the outputs into a block, resizing the outputs as necessary.
    resize!(times, j - 1)
    resize!(values, j - 1)
    return Block(times, values)
end
