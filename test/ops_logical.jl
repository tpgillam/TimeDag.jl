b_boolean = Block([
    DateTime(2000, 1, 1) => true,
    DateTime(2000, 1, 2) => false,
    DateTime(2000, 1, 3) => true,
    DateTime(2000, 1, 4) => true,
])

n_boolean = TimeDag.block_node(b_boolean)

@testset "unary" begin
    for op in [!]
        @testset "$op" begin
            @test _eval(op(n_boolean)) == _mapvalues(op, b_boolean)
        end
    end
end

@testset "binary" begin
    for op in (>, <, >=, <=)
        @testset "$op" begin
            _test_binary_op(op)
        end
    end
end
