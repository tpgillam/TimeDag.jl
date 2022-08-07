@testset "equality" begin
    @test TimeDag.Constant(1) == TimeDag.Constant(1)
    @test isequal(TimeDag.Constant(1), TimeDag.Constant(1))
    @test hash(TimeDag.Constant(1)) == hash(TimeDag.Constant(1))

    @test TimeDag.Constant(1.0) != TimeDag.Constant(1)
    @test !isequal(TimeDag.Constant(1.0), TimeDag.Constant(1))

    @test TimeDag.Constant(1) == TimeDag.Constant{Int64}(1)
    @test TimeDag.Constant{Number}(1) != TimeDag.Constant{Int64}(1)
end

@testset "constant propagation" begin
    n1 = constant(1)
    n2 = constant(2)

    @test n1 === constant(1)

    @test -n1 === constant(-1)
    @test exp(n1) === constant(exp(1))
    @test log(n1) === constant(0.0)

    @test n1 + n2 === constant(3)
    @test n1 - n2 === constant(-1)

    @test lag(n1, 2) === constant(1)
end

@testset "explicit type specification" begin
    @test constant(Int64, 1) === constant(1)
    n = constant(Number, 1)
    @test n === constant(Number, 1)
    @test value_type(n) == Number
    @test_throws MethodError constant(String, 1)
end

@testset "evaluate" begin
    for t_start in [DateTime(2020), DateTime(2021)]
        @test _evaluate(constant(3), t_start, t_start + Day(1)) == Block([t_start => 3])
    end
end
