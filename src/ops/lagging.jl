"""A node which lags its input by a fixed number of knots."""
struct Lag{T} <: NodeOp{T}
    n::Int64
end

struct LagState{T} <: NodeEvaluationState
    # A buffer of the last number of values required.
    value_buffer::CircularBuffer{T}
end

function create_evaluation_state(::Tuple{Node}, op::Lag{T}) where {T}
    return LagState(CircularBuffer{T}(op.n))
end

function run_node!(
    op::Lag{T},
    state::LagState{T},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{T},
) where {T}
    # The input is empty, so regardless of the state we cannot lag onto anything.
    # The state is unmodified, and return the empty block.
    isempty(input) && return input

    w = op.n  # The window length.
    ni = length(input)  # The input length.
    ns = length(state.value_buffer)  # The state buffer length.

    # The output length.
    #   - at most the input size
    #   - at most total number of knots available in this batch: max((ns + ni) - w, 0)
    no = min(ni, max((ns + ni) - w, 0))

    # The number of elements to take from the state buffer.
    #   - at most the window size
    #   - at most the number of available elements in the buffer
    #   - at most the output size
    m = min(w, ns, no)

    times = @inbounds @view(input.times[(1 + ni - no):end])
    values = if m == 0
        @inbounds @view(input.values[1:no])
    else
        # Merge values from the state and in the Block.
        result = _allocate_values(T, no)
        for i in 1:m
            @inbounds result[i] = popfirst!(state.value_buffer)
        end
        @inbounds result[(m + 1):end] = @view(input.values[1:(no - m)])
        result
    end

    # Update the state with the remaining values in the input.
    @inbounds append!(state.value_buffer, @view(input.values[(1 + no - m):end]))

    return Block(unchecked, times, values)
end

"""
    lag(x::Node, n::Integer)

Construct a node which takes values from `x`, but lags them by `n` knots.

This means that we do not introduce any new timestamps that do not appear in `x`, however
we will not emit knots for the first `n` values that appear when evaluating `x`.
"""
function lag(x::Node, n::Integer)
    n < 0 && throw(ArgumentError("Cannot lag by $n."))
    # Lagging by zero is a no-op.
    n == 0 && return x
    # Constant and empty nodes shouldn't be affected by lagging.
    _is_constant(x) && return x
    _is_empty(x) && return x

    return obtain_node((x,), Lag{value_type(x)}(n))
end

"""A node which lags its input by a fixed time duration."""
struct TLag{T} <: NodeOp{T}
    w::Millisecond
end

mutable struct TLagState{T} <: NodeEvaluationState
    # We don't know how many knots history we will have to keep.
    buffer::Block{T}
end

create_evaluation_state(::Tuple{Node}, ::TLag{T}) where {T} = TLagState(Block{T}())

function run_node!(
    op::TLag{T},
    state::TLagState{T},
    time_start::DateTime,  # time_start
    time_end::DateTime,  # time_end
    input::Block{T},
) where {T}
    # This is all history available to us, including the current block.
    # NB That `vcat` is optimimsed to avoid allocation if the existing buffer or `input`
    # is empty.
    history = vcat(state.buffer, input)

    # Select the period of history that we should be returning.
    view_start = time_start - op.w
    view_end = time_end - op.w
    view_history = _slice(history, view_start, view_end)

    # Store the rest in the state.
    # TODO This is slightly inefficient because we are repeating a binary search to locate
    # `view_end`, and we know that `time_end` is at the end of `history`.
    state.buffer = _slice(history, view_end, time_end)

    # Now we modify the times of the knots that we're outputting in the new block.
    return Block(unchecked, view_history.times .+ op.w, view_history.values)
end

"""
    lag(x::Node, w::TimePeriod)

Construct a node which takes values from `x`, but lags them by period `w`.
"""
function lag(x::Node, w::TimePeriod)
    w = Millisecond(w)

    w < Millisecond(0) && throw(ArgumentError("Cannot lag by $w."))
    # Optimisation.
    w == Millisecond(0) && return x
    # Constant and empty nodes shouldn't be affected by lagging.
    _is_constant(x) && return x
    _is_empty(x) && return x

    return obtain_node((x,), TLag{value_type(x)}(w))
end

"""
    diff(x::Node[, n=1])

Compute the `n`-knot difference of `x`, i.e. `x - lag(x, n)`.
"""
function Base.diff(x::Node, n::Integer=1)
    n > 0 || throw(ArgumentError("n must be positive, got $n"))
    return x - lag(x, n)
end
