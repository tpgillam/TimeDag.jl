#! format: off

@testset "filter" begin
    n = filter(<(3), n1)
    @test _eval(n) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 2,
    ])

    n = filter(>=(3), n1)
    @test _eval(n) == Block([
        DateTime(2000, 1, 3) => 3,
        DateTime(2000, 1, 4) => 4,
    ])
end

@testset "skipmissing" begin
    # If no missing inputs, should be a no-op.
    n = empty_node(Int64)
    @test value_type(n) == Int64
    @test n === skipmissing(n)

    # Constant semantics.
    @test constant(1) === skipmissing(constant(1))
    @test skipmissing(constant(missing)).op isa TimeDag.SkipMissing

    # Standard case.
    n = block_node(
        Block([
            DateTime(2000, 1, 1) => missing,
            DateTime(2000, 1, 2) => 2,
            DateTime(2000, 1, 3) => 3,
            DateTime(2000, 1, 4) => missing,
        ]),
    )
    @test value_type(n) == Union{Missing,Int64}
    n2 = skipmissing(n)
    @test value_type(n2) == Int64

    result = _evaluate(n2, DateTime(2000, 1, 1), DateTime(2000, 1, 5))
    @test value_type(result) == Int64
    @test result == Block([
        DateTime(2000, 1, 2) => 2,
        DateTime(2000, 1, 3) => 3,
    ])
end

#! format: on
