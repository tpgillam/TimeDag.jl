b1 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
    DateTime(2000, 1, 5) => 5,
    DateTime(2000, 1, 6) => 6,
    DateTime(2000, 1, 7) => 7,
])

n1 = block_node(b1)

_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

_mapvalues(f, block::Block) = Block([time => f(value) for (time, value) in block])
_mapallvalues(f, block::Block) = Block(block.times, f(block.values))

@testset "sum" begin
    @testset "inception" begin
        @test _eval(TimeDag.sum(n1)) == _mapallvalues(cumsum, b1)
    end

    @testset "window" begin
        n = TimeDag.sum(n1, 3)
        block = _eval(n)
        block_ee_false = _eval(TimeDag.sum(n1, 3; emit_early=false))
        block_ee_true = _eval(TimeDag.sum(n1, 3; emit_early=true))
        @test block == block_ee_false

        expected = Block([
            DateTime(2000, 1, 1) => 1,
            DateTime(2000, 1, 2) => 3,
            DateTime(2000, 1, 3) => 6,
            DateTime(2000, 1, 4) => 9,
            DateTime(2000, 1, 5) => 12,
            DateTime(2000, 1, 6) => 15,
            DateTime(2000, 1, 7) => 18,
        ])

        # TODO implement 'slice' indexing on Block
        @test block_ee_false == Block(expected.times[3:end], expected.values[3:end])
        @test block_ee_true == expected
    end
end

@testset "prod" begin
    @testset "inception" begin
        @test _eval(TimeDag.prod(n1)) == _mapallvalues(cumprod, b1)
    end

    @testset "window" begin
        n = TimeDag.prod(n1, 3)
        block = _eval(n)
        block_ee_false = _eval(TimeDag.prod(n1, 3; emit_early=false))
        block_ee_true = _eval(TimeDag.prod(n1, 3; emit_early=true))
        @test block == block_ee_false

        expected = Block([
            DateTime(2000, 1, 1) => 1,
            DateTime(2000, 1, 2) => 1 * 2,
            DateTime(2000, 1, 3) => 1 * 2 * 3,
            DateTime(2000, 1, 4) => 2 * 3 * 4,
            DateTime(2000, 1, 5) => 3 * 4 * 5,
            DateTime(2000, 1, 6) => 4 * 5 * 6,
            DateTime(2000, 1, 7) => 5 * 6 * 7,
        ])

        # TODO implement 'slice' indexing on Block
        @test block_ee_false == Block(expected.times[3:end], expected.values[3:end])
        @test block_ee_true == expected
    end
end
