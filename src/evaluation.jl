"""
    EvaluationState

All state necessary for the evaluation of some nodes.

This should be created with [`start_at`](@ref).

# Fields
- `ordered_node_to_children::OrderedDict{Node,Set{Node}}`: a map from every node which we
    need to run, to its children. The ordering of the elements is such that, if evaluated in
    this order, all dependencies will be evaluated before they are required.
- `node_to_state::IdDict{Node,NodeEvaluationState}`: maintain the state for every node
    being evaluated.
- `current_time::DateTime`: the time to which this state corresponds.
- `evaluated_node_to_blocks::IdDict{Node,Vector{Block}}`: the output blocks that we care
    about.
"""
mutable struct EvaluationState
    ordered_node_to_children::OrderedDict{Node,Set{Node}}
    node_to_state::IdDict{Node,NodeEvaluationState}
    current_time::DateTime
    # TODO Decouple this from the evaluation state?
    evaluated_node_to_blocks::IdDict{Node,Vector{Block}}
end

function duplicate_internal(x::EvaluationState, stackdict::IdDict)
    y = EvaluationState(
        x.ordered_node_to_children,
        IdDict((
            node => duplicate_internal(state, stackdict) for
            (node, state) in x.node_to_state
        )),
        x.current_time,
        IdDict((node => copy(blocks) for (node, blocks) in x.evaluated_node_to_blocks)),
    )
    stackdict[x] = y
    return y
end

"""
Wrapper that avoids the need to define `create_evaluation_state` for stateless nodes.
"""
function _create_evaluation_state(node)
    return stateless(node) ? EMPTY_NODE_STATE : create_evaluation_state(node)
end

"""
    start_at(nodes, time_start::DateTime) -> EvaluationState

Create a sufficient [`EvaluationState`](@ref) for the evaluation of `nodes`.

Internally, this will determine the subgraph that needs evaluating, i.e. all the ancestors
of `nodes`, and create a [`NodeEvaluationState`](@ref) for each of these.
"""
function start_at(nodes, time_start::DateTime)::EvaluationState
    # Create empty evaluation state for all these, and return in some suitable pacakge.
    evaluation_order = ancestors(nodes)

    ordered_node_to_children = OrderedDict{Node,Set{Node}}(
        node => Set{Node}() for node in evaluation_order
    )

    for node in evaluation_order
        for parent in parents(node)
            push!(ordered_node_to_children[parent], node)
        end
    end

    return EvaluationState(
        ordered_node_to_children,
        IdDict(map(node -> node => _create_evaluation_state(node), evaluation_order)),
        time_start,
        IdDict((node => Block{value_type(node)}[] for node in nodes)),
    )
end

"""
    evaluate_until(state::EvaluationState, time_end::DateTime) -> EvaluationState

Perform an evaluation of the given `state` until `time_end`, and return the new state.
"""
function evaluate_until(state::EvaluationState, time_end::DateTime)
    return evaluate_until(duplicate(state), time_end)
end

"""
    evaluate_until!(state::EvaluationState, time_end::DateTime)

Update the evaluation state by performing the evalution for each node.

!!! Note
    `state` is mutated in this call; users may prefer to use [`evaluate_until`](@ref), which
    ensures that arguments are not mutated.
"""
function evaluate_until!(state::EvaluationState, time_end::DateTime)::EvaluationState
    # TODO Could we use dagger here to solve this & parallelism for us? I think the problem
    #   with this could be mutation - needs thought.
    #
    #   Also, initial experiments suggest that Dagger has about 100x overhead for simple
    #   graphs (about 30s for 10^5 nodes, compared to 0.3s for full evaluation of a simple
    #   TimeDag graph in single-threaded mode).
    #
    #   A reasonable approach is likely to allow the user to specify a scheduler when
    #   evaluating.

    #! format: off
    node_to_input_blocks = Dict(
        node => Vector{Block}(undef, length(parents(node)))
        for node in keys(state.ordered_node_to_children)
    )
    #! format: on

    for node in keys(state.ordered_node_to_children)
        node_state = state.node_to_state[node]

        # Retrieve the input blocks for all parents, and discard the reference.
        input_blocks = pop!(node_to_input_blocks, node)

        # Run the node.
        block = run_node!(
            node.op, node_state, state.current_time, time_end, input_blocks...
        )
        for child in state.ordered_node_to_children[node]
            # Place the block in the location(s) that this child expects to find it.
            for i_parent in findall(isequal(node), parents(child))
                node_to_input_blocks[child][i_parent] = block
            end
        end

        evaluated_blocks = get(state.evaluated_node_to_blocks, node, nothing)
        if !isnothing(evaluated_blocks)
            # The current node is of interest - persist its output onto the evaluation
            # state.
            # TODO maybe we need to provide a size hint for the initial evaluated_blocks.
            #   Base.grow_to! seems to be a minor hotspot
            push!(evaluated_blocks, block)
        end
    end

    state.current_time = time_end
    return state
end

"""
    evaluate(nodes::AbstractVector{Node}, t0, t1[; batch_interval]) -> Vector{Block}
    evaluate(node::Node, t0, t1[; batch_interval]) -> Block

Evaluate the specified node(s) over the specified time range `[t0, t1)`, and return the
corresponding [`Block`](@ref)(s).

If `nodes` have common dependencies, work will not be repeated when performing this
evaluation.
"""
function evaluate(
    nodes::AbstractVector{<:Node},
    time_start::DateTime,
    time_end::DateTime;
    batch_interval::Union{Nothing,TimePeriod}=nothing,
)
    state = start_at(nodes, time_start)
    if isnothing(batch_interval)
        # Evaluate in one go.
        evaluate_until!(state, time_end)
    else
        t = time_start
        while true
            t = min(time_end, t + batch_interval)
            evaluate_until!(state, t)
            # Break when we have evaluated up to the end of the interval.
            t < time_end || break
        end
    end
    return [reduce(vcat, state.evaluated_node_to_blocks[node]) for node in nodes]
end

function evaluate(
    node::Node, time_start::DateTime, time_end::DateTime; batch_interval=nothing
)
    return only(evaluate([node], time_start, time_end; batch_interval))
end
