"""
All state necessary for the evaluation of a graph, and the persistence of a few nodes in
this graph.

Some thoughts on requirements
    - should know which nodes we *care* about, for keeping outputs.
    - needs all ancestors & map to (mutable) states
    - should keep track of the current time.
    - should be copyable (to save current state) TODO
    - should contain output blocks??
"""
mutable struct EvaluationState
    evaluation_order::Vector{Node}
    node_to_state::IdDict{Node, NodeEvaluationState}
    current_time::DateTime
    evaluated_node_to_blocks::IdDict{Node, Vector{Block}}
end

function duplicate_internal(x::EvaluationState, stackdict::IdDict)
    y = EvaluationState(
        x.evaluation_order,
        IdDict((
            node => duplicate_internal(state, stackdict)
            for (node, state) in x.node_to_state
        )),
        x.current_time,
        IdDict((
            node => copy(blocks)
            for (node, blocks) in x.evaluated_node_to_blocks
        )),
    )
    stackdict[x] = y
    return y
end

function start_at(nodes, time_start::DateTime)::EvaluationState
    # Create empty evaluation state for all these, and return in some suitable pacakge.
    evaluation_order = ancestors(nodes...)
    return EvaluationState(
        evaluation_order,
        IdDict(map(node -> node => create_evaluation_state(node), evaluation_order)),
        time_start,
        IdDict((node => Block{value_type(node)}[] for node in nodes)),
    )
end

"""
    get_up_to!(state::EvaluationState, time_end::DateTime)

Update the evaluation state by performing the evalution for each node.
"""
function get_up_to!(state::EvaluationState, time_end::DateTime)::EvaluationState
    # FIXME This is really suboptimal, as we keep all inputs around even after we're done
    #   with them. Can certainly do better with a more appropriate data structure.

    # TODO Could we use dagger here to solve this & parallelism for us? I think the problem
    #   with this could be mutation - needs thought.

    node_to_block = IdDict{Node, Block}()

    for node in state.evaluation_order
        node_state = state.node_to_state[node]
        # Retrieve the input blocks for all parents.
        input_blocks = [node_to_block[parent] for parent in parents(node)]

        # Run the node.
        block = run_node!(
            node_state, node.op, state.current_time, time_end, input_blocks...
        )
        node_to_block[node] = block

        if haskey(state.evaluated_node_to_blocks, node)
            # The current node is of interest - persist its output onto the evaluation
            # state.
            push!(state.evaluated_node_to_blocks[node], block)
        end
    end

    state.current_time = time_end
    return state
end

"""
    evaluate(nodes::Vector{Node}, t0, t1; (batch_interval)) -> Vector{Block}
    evaluate(node::Node, t0, t1; (batch_interval)) -> Block

Evaluate the specified node(s) over the specified time range [t0, t1), and return the
corresponding Block(s).

If `nodes` have common dependencies, work will not be repeated when performing this
evaluation.
"""
function evaluate(
    nodes::AbstractVector{Node},
    time_start::DateTime,
    time_end::DateTime;
    batch_interval::Union{Nothing, TimePeriod}=nothing,
)
    state = start_at(nodes, time_start)
    if isnothing(batch_interval)
        # Evaluate in one go.
        get_up_to!(state, time_end)
    else
        t = time_start
        while true
            t = min(time_end, t + batch_interval)
            get_up_to!(state, t)
            # Break when we have evaluated up to the end of the interval.
            t < time_end || break
        end
    end
    # TODO Is using splatting a performance overhead over a vector if there are many blocks?
    return [vcat(state.evaluated_node_to_blocks[node]...) for node in nodes]
end

function evaluate(
    node::Node,
    time_start::DateTime,
    time_end::DateTime;
    batch_interval=nothing
)
    return only(evaluate([node], time_start, time_end; batch_interval))
end
