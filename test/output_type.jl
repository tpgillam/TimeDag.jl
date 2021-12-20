@testset "examples" begin
    @test TimeDag.output_type(/, Int64, Int64) == Float64
    @test TimeDag.output_type(/, Missing, Int64) == Missing
    @test TimeDag.output_type(/, Union{Missing,Int64}, Int64) == Union{Missing,Float64}
end
