const _UNARY_STUFF = [
    (:-, :Negate, b1),
    (:exp, :Exp, b1),
    (:log, :Log, b1),
    (:log10, :Log10, b1),
    (:log2, :Log2, b1),
    (:sqrt, :Sqrt, b1),
    (:cbrt, :Cbrt, b1),
    (:inv, :Inv, b1),
    (:!, :Not, b_boolean),
]

@testset "unary" begin
    for (op, node_op, block) in _UNARY_STUFF
        @testset "$op" begin
            @eval begin
                # Check basic evaluation.
                value = first($(block).values)
                node = TimeDag.block_node($block)
                @test _eval($op(node)) == _mapvalues($op, $block)

                # Check constant propagation.
                @test $op(constant(value)) === constant($op(value))

                # Two instances of the NodeOp instance should compare equal for equal
                # type parameters.
                T = typeof(value)
                @test TimeDag.$node_op{T}() == TimeDag.$node_op{T}()
                @test T != Float32
                @test TimeDag.$node_op{Float32}() != TimeDag.$node_op{T}()
            end
        end
    end

    @testset "inverse identities" begin
        @test -(-n1) === n1
        @test inv(inv(n1)) === n1
        @test !(!n_boolean) === n_boolean
    end
end

const _BINARY_STUFF = [
    (:+, :Add),
    (:-, :Subtract),
    (:*, :Multiply),
    (:/, :Divide),
    (:^, :Power),
    (:min, :Min),
    (:max, :Max),
    (:>, :Greater),
    (:<, :Less),
    (:>=, :GreaterEqual),
    (:<=, :LessEqual),
]

@testset "binary" begin
    for (op, node_op) in _BINARY_STUFF
        @testset "$op" begin
            @eval begin
                # Test evaluations with different alignments.
                _test_binary_op($op)

                # Test constant propagation.
                value = 2.0  # valid for all ops we're currently testing.
                @test $op(constant(value), constant(value)) === constant($op(value, value))
                @test $op(value, constant(value)) === constant($op(value, value))
                @test $op(constant(value), value) === constant($op(value, value))

                # Two instances of the NodeOp instance should compare equal for equal
                # type parameters.
                T = typeof(value)
                for A in (UnionAlignment, IntersectAlignment, LeftAlignment)
                    @test TimeDag.$node_op{T,A}() == TimeDag.$node_op{T,A}()
                    @test T != Float32
                    @test TimeDag.$node_op{Float32,A}() != TimeDag.$node_op{T,A}()
                end
            end
        end
    end
end
