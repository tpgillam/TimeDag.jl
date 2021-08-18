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
