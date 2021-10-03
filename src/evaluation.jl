"""
All state necessary for the evaluation of a graph, and the persistence of a few nodes in
this graph.

Some thoughts on requirements
    - should know which nodes we *care* about, for keeping outputs.
    - needs all ancestors & map to (mutable) states
    - should keep track of the current time.
    - should contain output blocks??
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

function start_at(nodes, time_start::DateTime)::EvaluationState
    # Create empty evaluation state for all these, and return in some suitable pacakge.
    evaluation_order = ancestors(nodes...)

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
    # TODO Could we use dagger here to solve this & parallelism for us? I think the problem
    #   with this could be mutation - needs thought.
    #
    #   Also, initial experiments suggest that Dagger has about 100x overhead for simple
    #   graphs (about 30s for 10^5 nodes, compared to 0.3s for full evaluation of a simple
    #   TimeDag graph in single-threaded mode).
    #
    #   A reasonable approach is likely to allow the user to specify a scheduler when
    #   evaluating.

    node_to_input_blocks = Dict(
        node => Vector{Block}(undef, length(parents(node)))
        for node in keys(state.ordered_node_to_children)
    )

    for node in keys(state.ordered_node_to_children)
        node_state = state.node_to_state[node]

        # Retrieve the input blocks for all parents, and discard the reference.
        input_blocks = pop!(node_to_input_blocks, node)

        # Run the node.
        block = run_node!(
            node_state, node.op, state.current_time, time_end, input_blocks...
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
            push!(evaluated_blocks, block)
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
    batch_interval::Union{Nothing,TimePeriod}=nothing,
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
    return [reduce(vcat, state.evaluated_node_to_blocks[node]) for node in nodes]
end

function evaluate(
    node::Node, time_start::DateTime, time_end::DateTime; batch_interval=nothing
)
    return only(evaluate([node], time_start, time_end; batch_interval))
end
