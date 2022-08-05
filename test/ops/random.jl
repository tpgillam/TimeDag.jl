@testset "rand" begin
    # Some arbitrary alignment
    x = iterdates()
    expected_times = _eval_fast(x).times
    rng = MersenneTwister()

    # Some test values of `S` that we should be able to pass to `rand`
    all_test_vals = (
        (1, 2.0, 2.0 + 0im),
        [1, 2],
        [1 2; 3 4],
        Set([1, 2, 3]),
        Dict(1 => "1", 2 => "2", 3 => "3"),
        1:3,
        Beta(2.0),
    )

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
            for S in all_test_vals
                n = rand(rng, x, S)
                @test n === rand(rng, x, S)
                eltypes = isa(S, Distribution) ? [eltype(S)] : typeof.(collect(S))
                eltype_ = foldl(Base.promote_typejoin, eltypes)
                # We want the value type of the node to be upper-bounded by the promotion
                # we did above, and lower bounded by each of the individual element types.
                # It is possible (but not necessary) that
                #   value_type(n) == eltype_
                # but in testing this was not, and need not be, the case.
                @test value_type(n) <: eltype_
                foreach(eltypes) do T_el
                    @test value_type(n) >: T_el
                end

                block = _eval(n)
                @test block.times == expected_times
                @test all(block.values) do value
                    isa(S, Distribution) ? insupport(S, value) : in(value, S)
                end

                # Verify that we get the same number from a TimeDag evaluation as using the
                # same random state.
                rng_copy = copy(rng)
                @test block.values == [rand(rng_copy, S) for _ in 1:length(block)]

                n = rand(x, S)
                @test n != rand(x, S)
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
            for S in all_test_vals
                for size_ in ((2,), (2, 3), (2, 3, 4))
                    n = rand(rng, x, S, size_)
                    @test n === rand(rng, x, S, size_)
                    @test n === rand(rng, x, S, size_...)
                    eltypes = isa(S, Distribution) ? [eltype(S)] : typeof.(collect(S))
                    eltype_ = foldl(Base.promote_typejoin, eltypes)
                    @test value_type(n) == Array{eltype_,length(size_)}

                    block = _eval(n)
                    @test block.times == expected_times
                    foreach(block.values) do value
                        @test size(value) == size_
                        # Each value in the block is going to be an array.
                        @test all(value) do value_
                            isa(S, Distribution) ? insupport(S, value_) : in(value_, S)
                        end
                    end

                    # Verify that we get the same number from a TimeDag evaluation as using
                    # the same random state.
                    rng_copy = copy(rng)
                    @test block.values ==
                        [rand(rng_copy, S, size_) for _ in 1:length(block)]

                    # Test without explicit rng
                    n = rand(x, S, size_)
                    @test n != rand(x, S, size_)
                    n = rand(x, S, size_...)
                    @test n != rand(x, S, size_...)
                end
            end
        end
    end

    @testset "invalid arguments" begin
        d = Beta(2.0)

        # Construct an arbitrary call to rand which ought to fail.
        @test_throws MethodError rand(x, d, d)
        @test_throws MethodError rand(rng, x, d, d)
        @test_throws MethodError rand(rng, x, d, d, 1, 2)
        @test_throws MethodError rand(rng, x, d, d, ())

        # If we provide an S which doesn't have a sampler, then we should fail early.
        @test_throws ArgumentError rand(x, 2.0)
    end
end
