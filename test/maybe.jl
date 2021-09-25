@testset "bits type" begin
    x = TimeDag.Maybe{Float64}()
    @test !TimeDag.valid(x)
    @test_throws ArgumentError TimeDag.value(x)
    # Checking that this *doesn't* throw, although it could return anything.
    TimeDag.unsafe_value(x)

    y = TimeDag.Maybe(3.0)
    @test TimeDag.valid(y)
    @test TimeDag.value(y) == 3.0
    @test TimeDag.unsafe_value(y) == 3.0
end

@testset "non bits type" begin
    x = TimeDag.Maybe{Vector{Float64}}()
    @test !TimeDag.valid(x)
    @test_throws ArgumentError TimeDag.value(x)
    # This accesses an undefined reference, which is illegal.
    @test_throws UndefRefError TimeDag.unsafe_value(x)

    y = TimeDag.Maybe([3.0])
    @test TimeDag.valid(y)
    @test TimeDag.value(y) == [3.0]
    @test TimeDag.unsafe_value(y) == [3.0]
end
