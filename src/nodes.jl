"""A node which just wraps a block."""
struct BlockNode{T} <: NodeOp{T}
    block::Block{T}
end

create_evaluation_state(::BlockNode) = _EMPTY_NODE_STATE

function run_node!(
    ::EmptyNodeEvaluationState,
    op::BlockNode{T},
    time_start::DateTime,
    time_end::DateTime
) where {T}
    return _slice(op.block, time_start, time_end)
end

# TODO Need to think about equality for BlockNode. It is used in equality testing for node,
# so we do *not* really want to do full equality checking on block's values since this could
# really slow down identity mapping.


# TODO This Lag type really shouldn't be type parameteised... we should store the
# type information on a node some other way?

"""A node which lags its input by a fixed number of knots."""
struct Lag{T} <: NodeOp{T}
    n::Int64
    # TODO verify that n > 0
end

struct LagState{T} <: NodeEvaluationState
    # A buffer of the last number of values required.
    value_buffer::CircularBuffer{T}
end

create_evaluation_state(op::Lag{T}) where {T} = LagState(CircularBuffer{T}(op.n))

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
    m = min(w, ns)  # The number of elements to take from the state buffer.
    no = max(m + ni - w, 0)  # The output length.
    # na = min(w - (ns - m), ni)  # The number of elements to append to the state buffer.

    # TODO @inbounds everywhere
    times = @view(input.times[1 + ni - no:end])
    values = if m == 0
        @view(input.values[1:no])
    else
        # Merge values from the state and in the Block.
        # TODO This is not necessarily a good constructor. See comment near definition of
        #   Block.
        result = Vector{T}(undef, no)
        for i in 1:m
            result[i] = popfirst!(state.value_buffer)
        end
        result[m + 1:end] = @view(input.values[1:1 + no - m])
        result
    end

    # Update the state with the remaining values.
    append!(state.value_buffer, @view(input.values[2 + no - m:end]))

    return Block(times, values)

    # FIXME There is AT LEAST one bug in the above, as we're currently returning more
    # values than times in a block :-(
    # TODO This needs lots of tests!



    # elseif isempty(state.value_buffer)
    #     # Optimisation - just need to deal with input block in this case & populate state.
    #     # FIXME This can go out-of-bounds.
    #     append!(state.value_buffer, @view(input.values[max(1, end - node.n + 1):end]))
    #     return Block(
    #         @view(input.times[1 + node.n:end]),
    #         @view(input.values[1:end - node.n]),
    #     )
    # else
    #     # We need to consume one or more values from the state.
    #     # The output size will be the same as the input size, less any history that we're
    #     # missing in the current state.
    #     out_length = length(input) - node.n + length(state.value_buffer)
    #     values = Vector{T}(undef, out_length)

    #     num_to_drop = node.n - length(state.value_buffer)
    #     times = @view(input.times[1 + num_to_drop:end])



    # end



    # n_history = length(state.value_buffer)
    # n_available = length(input)






    # num_to_reset =



    # if (out_length <= 0)
    #     # The output will be empty, but we may need to reset some state.
    #     # TODO
    #     # TODO
    #     # TODO
    #     # TODO
    # end

    # # TODO
    # # TODO
    # # TODO
end



# API -- should go in another file, probably?

block_node(block::Block) = obtain_node((), BlockNode(block))

function lag(node::Node, n::Integer)
    return if n == 0
        # Optimisation.
        node
    elseif n < 0
        throw(ArgumentError("Cannot lag by $n."))
    else
        obtain_node((node,), Lag{value_type(node)}(n))
    end
end
