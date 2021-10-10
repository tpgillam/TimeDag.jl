function _naive_lag(block::Block, lag::Int64)
    return Block(block.times[(1 + lag):end], block.values[1:(end - lag)])
end

@testset "lag" begin
    @testset "negative" begin
        @test_throws ArgumentError TimeDag.lag(n1, -1)
    end

    @testset "zero" begin
        # Lagging by zero knots should return identically the same node.
        @test TimeDag.lag(n1, 0) === n1
        @test TimeDag.lag(n2, 0) === n2
    end

    @testset "lag with one input knot" begin
        for n_lag in 1:3
            # n3 corresponds to a block with exactly one knot. So any amount of lagging
            # should then lead to a node which, when evaluated, gives a block with no knots.
            n = TimeDag.lag(n3, n_lag)

            @test value_type(n) == value_type(n3)
            @test _eval(n) == Block{value_type(n3)}()
        end
    end

    @testset "general" begin
        for n_lag in 0:10
            n = TimeDag.lag(n4, n_lag)
            @test value_type(n) == value_type(n4)
            @test _eval(n) == _naive_lag(b4, n_lag)
        end
    end
end
