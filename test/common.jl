"""
Partial function application.
"""
function partial(f, args...; kwargs...)
    function new_f(fargs...; fkwargs...)
        return f(args..., fargs...; kwargs..., fkwargs...)
    end
    return new_f
end

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
    evaluate_until!(state, t1)
    test_equivalent(only(state.evaluated_node_to_blocks[node]), block)
    evaluate_until!(copied_state, t1)
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
const b1 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
])

const b2 = Block([
    DateTime(2000, 1, 2) => 5,
    DateTime(2000, 1, 3) => 6,
    DateTime(2000, 1, 5) => 8,
])

const b3 = Block([
    DateTime(2000, 1, 1) => 15,
])

const b4 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
    DateTime(2000, 1, 5) => 5,
    DateTime(2000, 1, 6) => 6,
    DateTime(2000, 1, 7) => 7,
])

const b_boolean = Block([
    DateTime(2000, 1, 1) => true,
    DateTime(2000, 1, 2) => false,
    DateTime(2000, 1, 3) => true,
    DateTime(2000, 1, 4) => true,
])

const n1 = block_node(b1)
const n2 = block_node(b2)
const n3 = block_node(b3)
const n4 = block_node(b4)
const n_boolean = TimeDag.block_node(b_boolean)

const _T_START = DateTime(2000, 1, 1)
const _T_END = DateTime(2001, 1, 1)

_eval(n) = _evaluate(n, _T_START, _T_END)
# Evaluation when not wanting to perform tests.
_eval_fast(n) = evaluate(n, _T_START, _T_END)

"""
    _get_rand_svec_block(rng::AbstractRNG, dim::Int, n_obs::Int) -> Block

Get a block of value type `SVector{dim,Float64}`, of length `n_obs`, with random values.
"""
function _get_rand_svec_block(rng::AbstractRNG, dim::Int, n_obs::Int)
    times = _T_START:Day(1):(_T_START + Day(n_obs - 1))
    values = [SVector{dim}(rand(rng, dim)) for _ in 1:n_obs]
    return Block(times, values)
end

"""
    _get_rand_vec_block(rng::AbstractRNG, dim::Int, n_obs::Int) -> Block

Get a block of value type `Vector{Float64}`, of length `n_obs`, with random values.
"""
function _get_rand_vec_block(rng::AbstractRNG, dim::Int, n_obs::Int)
    times = _T_START:Day(1):(_T_START + Day(n_obs - 1))
    values = [rand(rng, dim) for _ in 1:n_obs]
    return Block(times, values)
end

function _test_unary_op(f_timedag, block::Block, f=f_timedag)
    # Check basic evaluation.
    value = first(block.values)
    node = block_node(block)
    @test _eval(f_timedag(node)) == _mapvalues(f, block)

    # Check constant propagation.
    @test f_timedag(constant(value)) == constant(f(value))
    @test f_timedag(constant(value)) === constant(f(value))

    # Two instances of the NodeOp instance should compare equal for equal
    # type parameters.
    T = typeof(value)
    @test TimeDag.SimpleUnary{f,T}() == TimeDag.SimpleUnary{f,T}()
    @test T != Float32
    @test TimeDag.SimpleUnary{f,Float32}() != TimeDag.SimpleUnary{f,T}()
end

function _test_binary_op(f_timedag, f=f_timedag)
    # Common (fast) alignment.
    # Should apply for *any* user choice of alignment.
    for alignment in (UNION, LEFT, INTERSECT)
        n = f_timedag(n1, n1, alignment)
        block = _eval(n)
        @test block == Block([
            DateTime(2000, 1, 1) => f(1, 1),
            DateTime(2000, 1, 2) => f(2, 2),
            DateTime(2000, 1, 3) => f(3, 3),
            DateTime(2000, 1, 4) => f(4, 4),
        ])
        # For fast alignment, we expect *identical* timestamps as on the input.
        @test block.times === b1.times
    end

    # Union alignment.
    n = f_timedag(n1, n2)
    @test n === f_timedag(n1, n2, UNION)
    block = _eval(n)
    @test block == Block([
        DateTime(2000, 1, 2) => f(2, 5),
        DateTime(2000, 1, 3) => f(3, 6),
        DateTime(2000, 1, 4) => f(4, 6),
        DateTime(2000, 1, 5) => f(4, 8),
    ])

    # Intersect alignment.
    n = f_timedag(n1, n2, INTERSECT)

    @test _eval(n) == Block([
        DateTime(2000, 1, 2) => f(2, 5),
        DateTime(2000, 1, 3) => f(3, 6),
    ])

    # Left alignment
    n = f_timedag(n1, n2, LEFT)
    @test _eval(n) == Block([
        DateTime(2000, 1, 2) => f(2, 5),
        DateTime(2000, 1, 3) => f(3, 6),
        DateTime(2000, 1, 4) => f(4, 6),
    ])

    # Catch edge-case in which there was a bug.
    @test _eval(f_timedag(n2, n3, LEFT)) == Block([
        DateTime(2000, 1, 2) => f(5, 15),
        DateTime(2000, 1, 3) => f(6, 15),
        DateTime(2000, 1, 5) => f(8, 15),
    ])
    @test _eval(f_timedag(n3, n2, LEFT)) == Block{Int64}()

    # Test constant propagation.
    value = 2.0  # valid for all ops we're currently testing.
    @test f_timedag(constant(value), constant(value)) === constant(f(value, value))
    @test f_timedag(value, constant(value)) === constant(f(value, value))
    @test f_timedag(constant(value), value) === constant(f(value, value))

    # Two instances of the NodeOp instance should compare equal for equal
    # type parameters.
    T = typeof(value)
    for A in (UnionAlignment, IntersectAlignment, LeftAlignment)
        @test TimeDag.SimpleBinary{f,T,A}() == TimeDag.SimpleBinary{f,T,A}()
        @test T != Float32
        @test TimeDag.SimpleBinary{f,Float32,A}() != TimeDag.SimpleBinary{f,T,A}()
    end
end

#! format: on
