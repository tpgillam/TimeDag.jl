@testset "constant propagation" begin
    n1 = constant(1)
    n2 = constant(2)

    @test n1 === constant(1)

    @test -n1 === constant(-1)
    @test exp(n1) === constant(exp(1))
    @test log(n1) === constant(0.0)

    @test n1 + n2 === constant(3)
    @test n1 - n2 === constant(-1)

    @test TimeDag.lag(n1, 2) === constant(1)
end

@testset "evaluate" begin
    for t_start in [DateTime(2020), DateTime(2021)]
        @test _evaluate(constant(3), t_start, t_start + Day(1)) == Block([t_start => 3])
    end
end
