"""
Doesn't fail iff the two blocks are equivalent.
Blocks are equivalent if they represent equal time-series, even if the representations of
those time series are different (e.g. a range vs a vector)
"""
function test_equivalent(x::Block, y::Block)
    # Convert the blocks to a standard representation.
    x = Block(collect(x))
    y = Block(collect(y))
    @test x == y
end

"""
Evaluate in several different ways, and ensure that they are all equivalent.
"""
function _evaluate(node::Node, t0::DateTime, t1::DateTime)
    # Standard evaluation in one go.
    block = evaluate(node, t0, t1)

    # Evaluation with a batch interval.
    for divisions in [1, 2, 3, 4, 5, 13]
        # We don't care exactly what batch interval we get, just pick something that roughly
        # works.
        batch_interval, _ = divrem(t1 - t0, divisions)
        test_block = evaluate(node, t0, t1; batch_interval)
        test_equivalent(test_block, block)
    end

    # Re-evaluation, and copying state.
    state = start_at([node], t0)
    copied_state = duplicate(state)
    get_up_to!(state, t1)
    test_equivalent(only(state.evaluated_node_to_blocks[node]), block)
    get_up_to!(copied_state, t1)
    test_equivalent(only(copied_state.evaluated_node_to_blocks[node]), block)

    return block
end

"""
Map the given function over each of the block's values.
"""
_mapvalues(f, block::Block) = Block([time => f(value) for (time, value) in block])
