@testset "right" begin
    _test_binary_op(TimeDag.right, (x, y) -> y)
end

@testset "left" begin
    _test_binary_op(TimeDag.left, (x, y) -> x)
end

@testset "align" begin
    @test _eval(TimeDag.align(n4, n1)) == b1
    @test _eval(TimeDag.align(n1, n4)) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 2,
        DateTime(2000, 1, 3) => 3,
        DateTime(2000, 1, 4) => 4,
        DateTime(2000, 1, 5) => 4,
        DateTime(2000, 1, 6) => 4,
        DateTime(2000, 1, 7) => 4,
    ])
end
