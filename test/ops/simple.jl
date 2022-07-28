const _UNARY_STUFF = [
    (abs, b1),
    (exp, b1),
    (log, b1),
    (log10, b1),
    (log2, b1),
    (sqrt, b1),
    (cbrt, b1),
    (sign, b1),
    (tan, b1),
    (sin, b1),
    (cos, b1),
    (!, b_boolean),
    (-, b1),
    (inv, b1),
]

@testset "unary" begin
    for (f, block) in _UNARY_STUFF
        @testset "$f" begin
            _test_unary_op(f, block)
        end
    end

    @testset "inverse identities" begin
        @test -(-n1) === n1
        @test inv(inv(n1)) === n1
        @test !(!n_boolean) === n_boolean
    end

    @testset "difference of DateTime" begin
        block = Block(b4.times, b4.times)
        n = block_node(block)
        @test value_type(n) == DateTime
        n_diff = n - n
        @test value_type(n_diff) == Millisecond
    end
end

# FIXME: really need extended tests (especially for dot) where we use vector inputs too.
const _BINARY_FUNCTIONS = [+, -, *, /, ^, min, max, >, <, >=, <=, dot]

@testset "binary" begin
    for f in _BINARY_FUNCTIONS
        @testset "$f" begin
            # Test evaluations with different alignments.
            _test_binary_op(f)
        end
    end
end
