function _naive_lag(block::Block, lag::Int64)
    return Block(block.times[(1 + lag):end], block.values[1:(end - lag)])
end

_naive_lag(block::Block, lag::TimePeriod) = Block(block.times .+ lag, block.values)

function _naive_diff(block::Block, lag::Int64)
    lagged_block = _naive_lag(block, lag)
    return Block(lagged_block.times, block.values[(1 + lag):end] - lagged_block.values)
end

@testset "lag" begin
    @testset "negative" begin
        @test_throws ArgumentError lag(n1, -1)
        @test_throws ArgumentError lag(n1, -Hour(1))
    end

    @testset "zero" begin
        # Lagging by zero knots should return identically the same node.
        @test lag(n1, 0) === n1
        @test lag(n2, 0) === n2

        @test lag(n1, Hour(0)) === n1
        @test lag(n2, Second(0)) === n2
    end

    @testset "lag with one input knot" begin
        for n_lag in 1:3
            # n3 corresponds to a block with exactly one knot. So any amount of lagging
            # should then lead to a node which, when evaluated, gives a block with no knots.
            n = lag(n3, n_lag)

            @test value_type(n) == value_type(n3)
            @test _eval(n) == Block{value_type(n3)}()
        end
    end

    @testset "general" begin
        for n_lag in 0:10
            n = lag(n4, n_lag)
            @test value_type(n) == value_type(n4)
            @test _eval(n) == _naive_lag(b4, n_lag)
        end
    end

    @testset "time period" begin
        for w in [Millisecond(1), Second(1), Hour(1), Hour(48)]
            n = lag(n4, w)

            @test value_type(n) == value_type(n4)
            @test _eval(n) == _naive_lag(b4, w)
        end
    end
end

@testset "diff" begin
    @testset "non-positive" begin
        @test_throws ArgumentError diff(n1, -1)
        @test_throws ArgumentError diff(n1, 0)
    end

    @testset "general" begin
        @test diff(n4, 1) === diff(n4)
        for n_lag in 1:10
            n = diff(n4, n_lag)
            @test value_type(n) == value_type(n4)
            @test _eval(n) == _naive_diff(b4, n_lag)
        end
    end
end
