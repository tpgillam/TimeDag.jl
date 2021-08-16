"""A node which just wraps a block."""
struct BlockNode{T} <: NodeOp{T}
    block::Block{T}
end

create_evaluation_state(::Tuple{}, ::BlockNode) = _EMPTY_NODE_STATE

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

"""A node which fundamentally represents a constant available over all time."""
struct Constant{T} <: NodeOp{T}
    value::T
end

function Base.show(io::IO, op::Constant)
    return print(io, "$(typeof(op).name.name){$(value_type(op))}($(op.value))")
end

mutable struct ConstantState <: NodeEvaluationState
    ticked::Bool
    ConstantState() = new(false)
end

create_evaluation_state(::Tuple{}, ::Constant) = ConstantState()

_is_constant(::NodeOp) = false
_is_constant(::Constant) = true
_is_constant(node::Node) = _is_constant(node.op)

"""Identity if the argument is a node, otherwise wrap it in a constant node."""
_ensure_node(node::Node) = node
_ensure_node(value::Any) = obtain_node((), Constant(value))

function run_node!(
    state::ConstantState,
    op::Constant{T},
    time_start::DateTime,
    ::DateTime,  # time_end
) where {T}
    # The convention is that we emit a single knot at the start of the evaluation interval.
    return if state.ticked
        Block{T}()
    else
        state.ticked = true
        Block([time_start], [op.value])
    end
end


"""A node which lags its input by a fixed number of knots."""
struct Lag{T} <: NodeOp{T}
    n::Int64
    # TODO verify that n > 0
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
    m = min(w, ns)  # The number of elements to take from the state buffer.
    no = max(m + ni - w, 0)  # The output length.
    # na = min(w - (ns - m), ni)  # The number of elements to append to the state buffer.

    # TODO @inbounds everywhere
    times = @view(input.times[1 + ni - no:end])
    values = if m == 0
        @view(input.values[1:no])
    else
        # Merge values from the state and in the Block.
        result = _allocate_values(T, n)
        for i in 1:m
            result[i] = popfirst!(state.value_buffer)
        end
        result[m + 1:end] = @view(input.values[1:1 + no - m])
        result
    end

    # Update the state with the remaining values.
    append!(state.value_buffer, @view(input.values[2 + no - m:end]))

    return Block(times, values)

    # TODO This needs lots of tests!
end

struct Negate{T} <: UnaryNodeOp{T} end
operator(::Negate) = -

struct Add{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Add) = +

struct Subtract{T, A} <: BinaryAlignedNodeOp{T, A} end
operator(::Subtract) = -


# API -- should go in another file, probably?

# TODO all these need documentation!

block_node(block::Block) = obtain_node((), BlockNode(block))

constant(value::T) where {T} = obtain_node((), Constant(value))

function lag(node::Node, n::Integer)
    return if n == 0
        # Optimisation.
        node
    elseif n < 0
        throw(ArgumentError("Cannot lag by $n."))
    elseif _is_constant(node)
        # Constant nodes shouldn't be affected by lagging.
        node
    else
        obtain_node((node,), Lag{value_type(node)}(n))
    end
end

function negate(node::Node)
    if _is_constant(node)
        return constant(-node.op.value)
    end

    T = value_type(node)
    return obtain_node((node,), Negate{T}())
end

function add(node_l, node_r; alignment::Type{A}=DEFAULT_ALIGNMENT) where {A <: Alignment}
    node_l = _ensure_node(node_l)
    node_r = _ensure_node(node_r)
    if _is_constant(node_l) && _is_constant(node_r)
        # Constant propagation.
        return constant(node_l.op.value + node_r.op.value)
    end
    # Figure out the promotion of types from combining left & right.
    T = promomte_type(value_type(node_l), value_type(node_r))
    return obtain_node((node_l, node_r), Add{T, alignment}())
end

function subtract(
    node_l,
    node_r;
    alignment::Type{A}=DEFAULT_ALIGNMENT,
) where {A <: Alignment}
    node_l = _ensure_node(node_l)
    node_r = _ensure_node(node_r)
    if _is_constant(node_l) && _is_constant(node_r)
        # Constant propagation.
        return constant(node_l.op.value - node_r.op.value)
    end

    # Figure out the promotion of types from combining left & right.
    T = promomte_type(value_type(node_l), value_type(node_r))
    return obtain_node((node_l, node_r), Subtract{T, alignment}())
end

# Shorthand

Base.:-(node::Node) = negate(node)

Base.:+(node_l::Node, node_r::Node) = add(node_l, node_r)
Base.:+(node_l::Node, node_r) = add(node_l, node_r)
Base.:+(node_l, node_r::Node) = add(node_l, node_r)

Base.:-(node_l::Node, node_r::Node) = subtract(node_l, node_r)
Base.:-(node_l::Node, node_r) = subtract(node_l, node_r)
Base.:-(node_l, node_r::Node) = subtract(node_l, node_r)

# TODO Identity mapping... probably just want a cache of empty blocks by T somewhere?
empty_node(T) = block_node(Block{T}())
