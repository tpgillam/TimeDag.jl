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

# Common functionality for testing binary operators that also perform alignment.
# Disable formatting, so as to permit more consistent layout of timeseries.
#! format: off
b1 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
])

b2 = Block([
    DateTime(2000, 1, 2) => 5,
    DateTime(2000, 1, 3) => 6,
    DateTime(2000, 1, 5) => 8,
])

b3 = Block([
    DateTime(2000, 1, 1) => 15,
])

b4 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
    DateTime(2000, 1, 5) => 5,
    DateTime(2000, 1, 6) => 6,
    DateTime(2000, 1, 7) => 7,
])

n1 = block_node(b1)
n2 = block_node(b2)
n3 = block_node(b3)
n4 = block_node(b4)

_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

function _test_binary_op(op_timedag, op=op_timedag)
    # Common (fast) alignment.
    # Should apply for *any* user choice of alignment.
    for alignment in (
            TimeDag.UnionAlignment, TimeDag.LeftAlignment, TimeDag.IntersectAlignment
        )
        n = op_timedag(n1, n1, alignment)
        block = _eval(n)
        @test block == Block([
            DateTime(2000, 1, 1) => op(1, 1),
            DateTime(2000, 1, 2) => op(2, 2),
            DateTime(2000, 1, 3) => op(3, 3),
            DateTime(2000, 1, 4) => op(4, 4),
        ])
        # For fast alignment, we expect *identical* timestamps as on the input.
        @test block.times === b1.times
    end

    # Union alignment.
    n = op_timedag(n1, n2)
    @test n === op_timedag(n1, n2, TimeDag.UnionAlignment)
    block = _eval(n)
    @test block == Block([
        DateTime(2000, 1, 2) => op(2, 5),
        DateTime(2000, 1, 3) => op(3, 6),
        DateTime(2000, 1, 4) => op(4, 6),
        DateTime(2000, 1, 5) => op(4, 8),
    ])

    # Intersect alignment.
    n = op_timedag(n1, n2, TimeDag.IntersectAlignment)

    @test _eval(n) == Block([
        DateTime(2000, 1, 2) => op(2, 5),
        DateTime(2000, 1, 3) => op(3, 6),
    ])

    # Left alignment
    n = op_timedag(n1, n2, TimeDag.LeftAlignment)
    @test _eval(n) == Block([
        DateTime(2000, 1, 2) => op(2, 5),
        DateTime(2000, 1, 3) => op(3, 6),
        DateTime(2000, 1, 4) => op(4, 6),
    ])

    # Catch edge-case in which there was a bug.
    @test _eval(op_timedag(n2, n3, TimeDag.LeftAlignment)) == Block([
        DateTime(2000, 1, 2) => op(5, 15),
        DateTime(2000, 1, 3) => op(6, 15),
        DateTime(2000, 1, 5) => op(8, 15),
    ])
    @test _eval(op_timedag(n3, n2, TimeDag.LeftAlignment)) == Block{Int64}()
end

#! format: on
