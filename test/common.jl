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
    @test isequal(x, y)
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
Map the given function over each of the block's times & values.
"""
_map(f, block::Block) = Block([time => f(time, value) for (time, value) in block])

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

"""
    _get_rand_block(rng::AbstractRNG, n_obs::Int) -> Block

Get a block of value type `Float64`, of length `n_obs`, with random values.
"""
function _get_rand_block(rng::AbstractRNG, n_obs::Int)
    times = _T_START:Day(1):(_T_START + Day(n_obs - 1))
    values = rand(rng, n_obs)
    return Block(times, values)
end

function _test_unary_op(f_timedag, block::Block, f=f_timedag; time_agnostic::Bool=true)
    ft = time_agnostic ? (_, x) -> f(x) : f

    # Check basic evaluation.
    value = first(block.values)
    node = block_node(block)
    @test _eval(f_timedag(node)) == _map(ft, block)

    if time_agnostic
        # Check constant propagation (only relevant for time agnostic nodes).
        @test f_timedag(constant(value)) == constant(f(value))
        @test f_timedag(constant(value)) === constant(f(value))
    end

    # Two instances of the NodeOp instance should compare equal for equal
    # type parameters.
    T = typeof(value)
    @test T != Float32
    for ta in (true, false)
        @test TimeDag.SimpleUnary{f,ta,T}() == TimeDag.SimpleUnary{f,ta,T}()
        @test TimeDag.SimpleUnary{f,ta,Float32}() != TimeDag.SimpleUnary{f,ta,T}()
    end
end

function _test_binary_op(f_timedag, f=f_timedag; time_agnostic::Bool=true)
    ft = time_agnostic ? (_, x, y) -> f(x, y) : f

    @testset "Common (fast) alignment" begin
        # Should apply for *any* user choice of alignment.
        for alignment in (UNION, LEFT, INTERSECT)
            n = f_timedag(n1, n1, alignment)
            block = _eval(n)
            @test block == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), 1, 1),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 2),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 3),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 4),
            ])
            # For fast alignment, we expect *identical* timestamps as on the input.
            @test block.times === b1.times
        end
    end

    @testset "union alignment" begin
        n = f_timedag(n1, n2)
        @test n === f_timedag(n1, n2, UNION)
        block = _eval(n)
        @test block == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6),
            DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6),
            DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 4, 8),
        ])
    end

    @testset "intersect alignment" begin
        n = f_timedag(n1, n2, INTERSECT)

        @test _eval(n) == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6),
        ])
    end

    @testset "left alignment" begin
        n = f_timedag(n1, n2, LEFT)
        @test _eval(n) == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6),
            DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6),
        ])

        # Catch edge-case in which there was a bug.
        @test _eval(f_timedag(n2, n3, LEFT)) == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 5, 15),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 6, 15),
            DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 8, 15),
        ])
        @test _eval(f_timedag(n3, n2, LEFT)) == Block{Int64}()
    end

    if time_agnostic
        @testset "constant propagation" begin
            value = 2.0  # valid for all ops we're currently testing.
            @test f_timedag(constant(value), constant(value)) === constant(f(value, value))
            @test f_timedag(value, constant(value)) === constant(f(value, value))
            @test f_timedag(constant(value), value) === constant(f(value, value))
        end
    end

    # Two instances of the NodeOp instance should compare equal for equal
    # type parameters.
    T = Float64
    for A in (UnionAlignment, IntersectAlignment, LeftAlignment)
        for ta in (true, false)
            @test TimeDag.SimpleBinary{f,ta,T,A}() == TimeDag.SimpleBinary{f,ta,T,A}()
            @test TimeDag.SimpleBinary{f,ta,Float32,A}() != TimeDag.SimpleBinary{f,ta,T,A}()
        end
    end

    @testset "initial values" begin
        # Initial value of wrong type.
        @test_throws ArgumentError f_timedag(n1, n2; initial_values=(-1, -2.0))

        @testset "union alignment" begin
            n = f_timedag(n1, n2; initial_values=(-1, -2))
            @test n === f_timedag(n1, n2, UNION; initial_values=(-1, -2))

            @test _eval(n) == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), 1, -2),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6),
                DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 4, 8),
            ])

            n = f_timedag(n2, n1; initial_values=(-1, -2))
            @test _eval(n) == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), -1, 1),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 5, 2),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 6, 3),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 6, 4),
                DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 8, 4),
            ])
        end

        @testset "left alignment" begin
            n = f_timedag(n1, n2, LEFT; initial_values=(-1, -2))
            # Initial left value should be ignored.
            @test n === f_timedag(n1, n2, LEFT; initial_values=(-42, -2))
            @test _eval(n) == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), 1, -2),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6),
            ])
        end

        # Intersect alignment
        @testset "intersect alignment" begin
            n = f_timedag(n1, n2, INTERSECT; initial_values=(-1, -2))
            # Initial values should always be ignored.
            @test n === f_timedag(n1, n2, INTERSECT)
        end
    end
end

function _test_ternary_op(f_timedag, f=f_timedag; time_agnostic::Bool=true)
    ft = time_agnostic ? (_, x, y, z) -> f(x, y, z) : f

    @testset "Common (fast) alignment" begin
        # Should apply for *any* user choice of alignment.
        for alignment in (UNION, LEFT, INTERSECT)
            n = f_timedag(n1, n1, n1, alignment)
            block = _eval(n)
            @test block == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), 1, 1, 1),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 2, 2),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 3, 3),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 4, 4),
            ])
            # For fast alignment, we expect *identical* timestamps as on the input.
            @test block.times === b1.times
        end
    end

    @testset "union alignment" begin
        n = f_timedag(n1, n2, n3)
        @test n === f_timedag(n1, n2, n3, UNION)
        block = _eval(n)
        @test block == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5, 15),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6, 15),
            DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6, 15),
            DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 4, 8, 15),
        ])
    end

    @testset "intersect alignment" begin
        n = f_timedag(n1, n2, n4, INTERSECT)

        @test _eval(n) == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5, 2),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6, 3),
        ])
    end

    @testset "left alignment" begin
        n = f_timedag(n1, n2, n3, LEFT)
        @test _eval(n) == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5, 15),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6, 15),
            DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6, 15),
        ])

        # Catch edge-case in which there was a bug.
        @test _eval(f_timedag(n2, n3, n1, LEFT)) == Block([
            DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 5, 15, 2),
            DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 6, 15, 3),
            DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 8, 15, 4),
        ])
        @test _eval(f_timedag(n3, n2, n1, LEFT)) == Block{Int64}()
    end

    if time_agnostic
        @testset "constant propagation" begin
            value = 2.0  # valid for all ops we're currently testing.
            cv = constant(value)
            cf = constant(f(value, value, value))
            @test f_timedag(cv, cv, cv) === cf
            @test f_timedag(cv, value, value) === cf
            @test f_timedag(value, cv, value) === cf
            @test f_timedag(value, value, cv) === cf
            @test f_timedag(cv, cv, value) === cf
            @test f_timedag(cv, value, cv) === cf
            @test f_timedag(value, cv, cv) === cf
        end
    end

    # Two instances of the NodeOp instance should compare equal for equal
    # type parameters.
    T = Float64
    for A in (UnionAlignment, IntersectAlignment, LeftAlignment)
        for ta in (true, false)
            @test TimeDag.SimpleNary{f,ta,3,T,A}() == TimeDag.SimpleNary{f,ta,3,T,A}()
            @test TimeDag.SimpleNary{f,ta,3,Float32,A}() != TimeDag.SimpleNary{f,ta,3,T,A}()
        end
    end

    @testset "initial values" begin
        # Initial value of wrong type.
        @test_throws ArgumentError f_timedag(n1, n2, n3; initial_values=(-1, -2.0, -3))

        @testset "union alignment" begin
            n = f_timedag(n1, n2, n3; initial_values=(-1, -2, -3))
            @test n === f_timedag(n1, n2, n3, UNION; initial_values=(-1, -2, -3))

            @test _eval(n) == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), 1, -2, 15),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5, 15),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6, 15),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6, 15),
                DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 4, 8, 15),
            ])

            n = f_timedag(n2, n1, n3; initial_values=(-1, -2, -3))
            @test _eval(n) == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), -1, 1, 15),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 5, 2, 15),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 6, 3, 15),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 6, 4, 15),
                DateTime(2000, 1, 5) => ft(DateTime(2000, 1, 5), 8, 4, 15),
            ])
        end

        @testset "left alignment" begin
            n = f_timedag(n1, n2, n3, LEFT; initial_values=(-1, -2, -3))
            # TODO Support this.
            # # Initial left value should be ignored.
            # @test n === f_timedag(n1, n2, n3, LEFT; initial_values=(-42, -2, -3))
            @test _eval(n) == Block([
                DateTime(2000, 1, 1) => ft(DateTime(2000, 1, 1), 1, -2, 15),
                DateTime(2000, 1, 2) => ft(DateTime(2000, 1, 2), 2, 5, 15),
                DateTime(2000, 1, 3) => ft(DateTime(2000, 1, 3), 3, 6, 15),
                DateTime(2000, 1, 4) => ft(DateTime(2000, 1, 4), 4, 6, 15),
            ])
        end

        # Intersect alignment
        @testset "intersect alignment" begin
            n = f_timedag(n1, n2, n3, INTERSECT; initial_values=(-1, -2, -3))
            # Initial values should always be ignored.
            @test n === f_timedag(n1, n2, n3, INTERSECT)
        end
    end
end

#! format: on
