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

    # Optimisations
    @test filter(>(0), constant(1)) === constant(1)
    @test filter(>(0), constant(-1)) === empty_node(Int64)
    @test filter(>(0), empty_node(Float64)) === empty_node(Float64)
    @test filter(>(0), empty_node(Int64)) === empty_node(Int64)
end

@testset "skipmissing" begin
    # If no missing inputs, should be a no-op.
    n = empty_node(Int64)
    @test value_type(n) == Int64
    @test n === skipmissing(n)

    # Constant and empty semantics.
    @test skipmissing(constant(1)) === constant(1)
    @test skipmissing(constant(Union{Missing,Int64}, 1)) === constant(1)
    @test skipmissing(constant(missing)) === empty_node(Union{})
    @test skipmissing(constant(Union{Float64,Missing}, missing)) === empty_node(Float64)
    @test skipmissing(empty_node(Float64)) === empty_node(Float64)
    @test skipmissing(empty_node(Union{Float64,Missing})) === empty_node(Float64)
    @test skipmissing(empty_node(Missing)) === empty_node(Union{})

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

@testset "zap_until" begin
    n = empty_node(Int64)
    @test zap_until(n, DateTime(2000)) === n

    @test _eval(zap_until(n1, DateTime(2000, 1, 3))) ==
        Block([
            DateTime(2000, 1, 3) => 3,
            DateTime(2000, 1, 4) => 4
        ])

    @test _eval(zap_until(n_boolean, DateTime(2000, 1, 3))) ==
        Block([
            DateTime(2000, 1, 3) => true,
            DateTime(2000, 1, 4) => true
        ])

    for cutoff in first(b4.times):Minute(133):last(b4.times)
        @test _eval(zap_until(n4, cutoff)) ==
            TimeDag._slice(b4, cutoff, last(b4.times) + Hour(1))
    end
end

#! format: on
