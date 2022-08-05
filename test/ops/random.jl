@testset "rand" begin
    # Some arbitrary alignment
    x = iterdates()
    expected_times = _eval_fast(x).times
    rng = MersenneTwister()

    @testset "scalar" begin
        n = rand(x)
        @test value_type(n) == Float64
        # calling multiple times should give different nodes, since we use a different rng.
        @test n != rand(x)

        # If we specify an explicit rng, then we should get identical nodes back.
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

        # No explicit rng.
        n = rand(x, Int32)
        @test n != rand(x, Int32)
        @test value_type(n) == Int32

        @testset "collections of values" begin
            for vals in (
                (1, 2.0, 2.0 + 0im),
                [1, 2],
                [1 2; 3 4],
                Set([1, 2, 3]),
                Dict(1 => "1", 2 => "2", 3 => "3"),
            )
                n = rand(rng, x, vals)
                @test n === rand(rng, x, vals)
                @test value_type(n) <: foldl(Base.promote_typejoin, typeof.(collect(vals)))

                block = _eval(n)
                @test block.times == expected_times
                @test all(in(vals), block.values)

                n = rand(x, vals)
                @test n != rand(x, vals)
            end
        end
    end

    @testset "array" begin
        @testset "size zero arrays" begin
            n = rand(x, Float64, ())
            @test value_type(n) == Array{Float64,0}
            n = rand(rng, x, Float64, ())
            @test value_type(n) == Array{Float64,0}
        end

        # If we specify an explicit rng, then we should get identical nodes back.
        n = rand(rng, x, Float64, (2,))
        @test n === rand(rng, x, Float64, (2,))
        @test n != rand(rng, x, Float64, (3,))
        @test n != rand(rng, x, Float64, (2, 3))

        @test rand(rng, x, Float64, (2,)) === rand(rng, x, 2)
        @test rand(rng, x, Float64, (2,)) === rand(rng, x, Float64, 2)
        @test rand(rng, x, Float64, (2, 3)) === rand(rng, x, 2, 3)
        @test rand(rng, x, Float64, (2, 3)) === rand(rng, x, 2, 3)
        @test rand(rng, x, Float64, (2, 3)) === rand(rng, x, Float64, 2, 3)

        @test value_type(n) == Vector{Float64}
        block = _eval(n)
        @test block.times == expected_times
        @test all(map(value -> all(0 .<= value .< 1), block.values))

        # Test value types when we don't have an explicit rng
        @test value_type(rand(x, 2)) == Vector{Float64}
        @test value_type(rand(x, Float64, (2,))) == Vector{Float64}
        @test value_type(rand(x, 2, 3)) == Matrix{Float64}
        @test value_type(rand(x, Float64, (2, 3))) == Matrix{Float64}
        @test value_type(rand(x, 2, 3, 4)) == Array{Float64,3}
        @test value_type(rand(x, Float64, (2, 3, 4))) == Array{Float64,3}

        @test value_type(rand(x, Int32, 2)) == Vector{Int32}
        @test value_type(rand(x, Int32, (2,))) == Vector{Int32}
        @test value_type(rand(x, Int32, 2, 3)) == Matrix{Int32}
        @test value_type(rand(x, Int32, (2, 3))) == Matrix{Int32}

        @testset "collections of values" begin
            for vals in (
                (1, 2.0, 2.0 + 0im),
                [1, 2],
                [1 2; 3 4],
                Set([1, 2, 3]),
                Dict(1 => "1", 2 => "2", 3 => "3"),
            )
                for size_ in ((2,), (2, 3), (2, 3, 4))
                    n = rand(rng, x, vals, size_)
                    @test n === rand(rng, x, vals, size_)
                    @test n === rand(rng, x, vals, size_...)
                    eltype = foldl(Base.promote_typejoin, typeof.(collect(vals)))
                    @test value_type(n) == Array{eltype,length(size_)}

                    block = _eval(n)
                    @test block.times == expected_times
                    foreach(block.values) do value
                        @test size(value) == size_
                        # Each value in the block is going to be an array.
                        @test all(in(vals), value)
                    end

                    # Test without explicit rng
                    n = rand(x, vals, size_)
                    @test n != rand(x, vals, size_)
                    n = rand(x, vals, size_...)
                    @test n != rand(x, vals, size_...)
                end
            end
        end
    end
end
