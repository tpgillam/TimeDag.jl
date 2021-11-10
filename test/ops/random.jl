@testset "rand" begin
    # Some arbitrary alignment
    x = iterdates()
    expected_times = _eval_fast(x).times

    @testset "scalar" begin
        n = rand(x)
        # calling multiple times should give different nodes, since we use a different rng.
        @test n != rand(x)

        # If we specify an explicit rng, then we should get identical nodes back.
        rng = MersenneTwister()
        n = rand(rng, x)
        @test n === rand(rng, x)

        @test value_type(n) == Float64
        block = _eval(n)
        @test block.times == expected_times
        @test all(0 .<= block.values .< 1)

        n = rand(rng, x, Int32)
        @test n === rand(rng, x, Int32)
        @test value_type(n) == Int32
        block = _eval(n)
        @test block.times == expected_times
        @test all(typemin(Int32) .<= block.values .<= typemax(Int32))
    end

    @testset "array" begin
        n = rand(x, ())
        @test value_type(n) == Array{Float64,0}

        # If we specify an explicit rng, then we should get identical nodes back.
        rng = MersenneTwister()
        n = rand(rng, x, (2,))
        @test n === rand(rng, x, (2,))
        @test n != rand(rng, x, (3,))
        @test n != rand(rng, x, (2, 3))

        @test rand(rng, x, (2,)) === rand(rng, x, 2)
        @test rand(rng, x, Float64, (2,)) === rand(rng, x, 2)
        @test rand(rng, x, (2,)) === rand(rng, x, Float64, 2)
        @test rand(rng, x, (2, 3)) === rand(rng, x, 2, 3)
        @test rand(rng, x, Float64, (2, 3)) === rand(rng, x, 2, 3)
        @test rand(rng, x, (2, 3)) === rand(rng, x, Float64, 2, 3)

        @test value_type(n) == Vector{Float64}
        block = _eval(n)
        @test block.times == expected_times
        @test all(map(value -> all(0 .<= value .< 1), block.values))
    end
end
