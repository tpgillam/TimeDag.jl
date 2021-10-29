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
    state::LagState{T},
    op::Lag{T},
    ::DateTime,  # time_start
    ::DateTime,  # time_end
    input::Block{T},
) where {T}
    if isempty(input)
        # The input is empty, so regardless of the state we cannot lag onto anything.
        # The state is unmodified, and return the empty block.
        return input
    end

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
    return if n == 0
        # Optimisation.
        x
    elseif n < 0
        throw(ArgumentError("Cannot lag by $n."))
    elseif _is_constant(x)
        # Constant nodes shouldn't be affected by lagging.
        x
    else
        obtain_node((x,), Lag{value_type(x)}(n))
    end
end

"""
    diff(x::Node[, n=1])

Compute the `n`-knot difference of `x`, i.e. `x - lag(x, n)`.
"""
function Base.diff(x::Node, n::Integer=1)
    n > 0 || throw(ArgumentError("n must be positive, got $n"))
    return x - lag(x, n)
end
