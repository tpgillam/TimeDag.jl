b1 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
])

b2 = Block([
    DateTime(2000, 1, 2) => 5,
    DateTime(2000, 1, 3) => 6,
    DateTime(2000, 1, 5) => 8,
])

b3 = Block([
    DateTime(2000, 1, 1) => 15,
])

n1 = block_node(b1)
n2 = block_node(b2)
n3 = block_node(b3)

_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

@testset "unary" begin
    for op in [-, exp, log, log10, log2, sqrt, cbrt]
        @testset "$op" begin
            @test _eval(op(n1)) == _mapvalues(op, b1)
        end
    end
end

@testset "binary" begin
    # TODO Refactor >, <, >=, <= to ops_logical.jl
    for op in (+, -, *, /, ^, >, <, >=, <=)
        @testset "$op" begin
            # Union alignment.
            n = op(n1, n2)
            @test n === op(n1, n2, TimeDag.UnionAlignment)
            block = _eval(n)
            @test block == Block([
                DateTime(2000, 1, 2) => op(2, 5),
                DateTime(2000, 1, 3) => op(3, 6),
                DateTime(2000, 1, 4) => op(4, 6),
                DateTime(2000, 1, 5) => op(4, 8),
            ])

            # Intersect alignment.
            n = op(n1, n2, TimeDag.IntersectAlignment)

            @test _eval(n) == Block([
                DateTime(2000, 1, 2) => op(2, 5),
                DateTime(2000, 1, 3) => op(3, 6),
            ])

            # Left alignment
            n = op(n1, n2, TimeDag.LeftAlignment)
            @test _eval(n) == Block([
                DateTime(2000, 1, 2) => op(2, 5),
                DateTime(2000, 1, 3) => op(3, 6),
                DateTime(2000, 1, 4) => op(4, 6),
            ])

            # Catch edge-case in which there was a bug.
            @test _eval(op(n2, n3, TimeDag.LeftAlignment)) == Block([
                DateTime(2000, 1, 2) => op(5, 15),
                DateTime(2000, 1, 3) => op(6, 15),
                DateTime(2000, 1, 5) => op(8, 15),
            ])
            @test _eval(op(n3, n2, TimeDag.LeftAlignment)) == Block{Int64}()
        end
    end
end
