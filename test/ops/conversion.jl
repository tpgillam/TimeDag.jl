@testset "convert_value" begin
    n1_float = convert_value(Float64, n1)
    @test value_type(n1_float) == Float64
    @test convert_value(Int64, n1) === n1
    @test convert_value(Float64, n1_float) === n1_float

    @test_throws ArgumentError convert_value(String, n1)

    # Supertypes that might not get converted.
    @test value_type(convert_value(Any, n1)) == Int64
    @test value_type(convert_value(Any, n1; upcast=false)) == Int64
    @test value_type(convert_value(Any, n1; upcast=true)) == Any
    @test value_type(convert_value(Number, n1; upcast=true)) == Number

    @test convert_value(Float64, constant(1)) === constant(1.0)
    @test convert_value(Float64, empty_node(Int64)) === empty_node(Float64)
    @test convert_value(Number, constant(1)) === constant(Int64, 1)
    @test convert_value(Number, constant(1); upcast=true) === constant(Number, 1)
    @test convert_value(Number, empty_node(Int64); upcast=true) === empty_node(Number)
end
