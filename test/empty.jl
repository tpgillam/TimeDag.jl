@testset "equality" begin
    @test TimeDag.Empty{Int64}() == TimeDag.Empty{Int64}()
    @test isequal(TimeDag.Empty{Int64}(), TimeDag.Empty{Int64}())
    @test hash(TimeDag.Empty{Int64}()) == hash(TimeDag.Empty{Int64}())

    @test TimeDag.Empty{Float64}() != TimeDag.Empty{Int64}()
    @test !isequal(TimeDag.Empty{Float64}(), TimeDag.Empty{Int64}())
end

@testset "empty propagation" begin
    n_int = empty_node(Int64)
    n_float = empty_node(Float64)
    n_bool = empty_node(Bool)

    @test n_int === empty_node(Int64)
    @test n_float === empty_node(Float64)

    @test -n_int === n_int
    @test exp(n_int) === n_float
    @test log(n_int) === n_float

    @test n_int + n_float === n_float
    @test n_int - n_float === n_float

    @test lag(n_int, 2) === n_int
    @test lag(n_int, Hour(1)) === n_int

    @test +(n_int, 1, UNION) === n_int
    @test +(n_int, 1, INTERSECT) === n_int
    @test +(n_int, 1, LEFT) === n_int
    @test +(1, n_int, LEFT) === n_int

    @test +(n_int, 1, UNION; initial_values=(0, 0)) === constant(1)
    @test +(n_int, 1, INTERSECT; initial_values=(0, 0)) === n_int
    @test +(n_int, 1, LEFT; initial_values=(0, 0)) === n_int
    @test +(1, n_int, LEFT; initial_values=(0, 0)) === constant(1)

    @test TimeDag.apply(min, n_int, n_bool, n_float) === n_float
    @test TimeDag.apply(min, n_int, false, n_float) === n_float
    @test TimeDag.apply(min, n_int, false, 1.0) === n_float
    @test TimeDag.apply(min, 1, false, n_float) === n_float

    initial_values = (0, false, 0.0)
    @test TimeDag.apply(min, n_int, n_bool, n_float; initial_values) === n_float
    @test TimeDag.apply(min, n_int, false, n_float; initial_values) === constant(0.0)
    @test TimeDag.apply(min, n_int, false, n_float, LEFT; initial_values) === n_float
    @test TimeDag.apply(min, n_int, false, n_float, INTERSECT; initial_values) === n_float
    @test TimeDag.apply(min, n_int, false, 1.0; initial_values) === constant(0.0)
    @test TimeDag.apply(min, n_int, false, 1.0, LEFT; initial_values) === n_float
    @test TimeDag.apply(min, n_int, false, 1.0, INTERSECT; initial_values) === n_float
    @test TimeDag.apply(min, 1, false, n_float; initial_values) === constant(0.0)
end

@testset "evaluate" begin
    for t_start in [DateTime(2020), DateTime(2021)]
        @test _evaluate(empty_node(Int64), t_start, t_start + Day(1)) == Block{Int64}()
    end
end
