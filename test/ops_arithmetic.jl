_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

@testset "unary" begin
    for op in [-, exp, log, log10, log2, sqrt, cbrt]
        @testset "$op" begin
            @test _eval(op(n1)) == _mapvalues(op, b1)
        end
    end

    @testset "inverse identities" begin
        @test -(-n1) === n1
    end
end

@testset "binary" begin
    for op in (+, -, *, /, ^)
        @testset "$op" begin
            _test_binary_op(op)
        end
    end
end
