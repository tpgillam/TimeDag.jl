const _UNARY_STUFF = [
    (:-, b1),
    (:exp, b1),
    (:log, b1),
    (:log10, b1),
    (:log2, b1),
    (:sqrt, b1),
    (:cbrt, b1),
    (:inv, b1),
    (:!, b_boolean),
]

@testset "unary" begin
    for (f, block) in _UNARY_STUFF
        @testset "$f" begin
            @eval begin
                # Check basic evaluation.
                value = first($(block).values)
                node = block_node($block)
                @test _eval($f(node)) == _mapvalues($f, $block)

                # Check constant propagation.
                @test $f(constant(value)) === constant($f(value))

                # Two instances of the NodeOp instance should compare equal for equal
                # type parameters.
                T = typeof(value)
                @test TimeDag.SimpleUnary{$f,T}() == TimeDag.SimpleUnary{$f,T}()
                @test T != Float32
                @test TimeDag.SimpleUnary{$f,Float32}() != TimeDag.SimpleUnary{$f,T}()
            end
        end
    end

    @testset "inverse identities" begin
        @test -(-n1) === n1
        @test inv(inv(n1)) === n1
        @test !(!n_boolean) === n_boolean
    end
end

const _BINARY_FUNCTIONS = [:+, :-, :*, :/, :^, :min, :max, :>, :<, :>=, :<=]

@testset "binary" begin
    for f in _BINARY_FUNCTIONS
        @testset "$f" begin
            @eval begin
                # Test evaluations with different alignments.
                _test_binary_op($f)

                # Test constant propagation.
                value = 2.0  # valid for all ops we're currently testing.
                @test $f(constant(value), constant(value)) === constant($f(value, value))
                @test $f(value, constant(value)) === constant($f(value, value))
                @test $f(constant(value), value) === constant($f(value, value))

                # Two instances of the NodeOp instance should compare equal for equal
                # type parameters.
                T = typeof(value)
                for A in (UnionAlignment, IntersectAlignment, LeftAlignment)
                    @test TimeDag.SimpleBinary{$f,T,A}() == TimeDag.SimpleBinary{$f,T,A}()
                    @test T != Float32
                    @test TimeDag.SimpleBinary{$f,Float32,A}() !=
                        TimeDag.SimpleBinary{$f,T,A}()
                end
            end
        end
    end
end
