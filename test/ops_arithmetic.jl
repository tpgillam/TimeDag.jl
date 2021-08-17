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
    DateTime(2000, 1, 1) => -5,
])

n1 = block_node(b1)
n2 = block_node(b2)
n3 = block_node(b3)

_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

@testset "add" begin
    # Union alignment.
    n = n1 + n2
    @test n === TimeDag.add(n1, n2; alignment=TimeDag.UnionAlignment)
    block = _eval(n)
    @test block == _eval(n2 + n1)  # Commutative
    @test block == Block([
        DateTime(2000, 1, 2) => 7,
        DateTime(2000, 1, 3) => 9,
        DateTime(2000, 1, 4) => 10,
        DateTime(2000, 1, 5) => 12,
    ])

    # Intersect alignment.
    n = TimeDag.add(n1, n2; alignment=TimeDag.IntersectAlignment)
    block = _eval(n)
    @test block == _eval(TimeDag.add(n2, n1; alignment=TimeDag.IntersectAlignment))

    @test block == Block([
        DateTime(2000, 1, 2) => 7,
        DateTime(2000, 1, 3) => 9,
    ])

    # Left alignment
    n = TimeDag.add(n1, n2; alignment=TimeDag.LeftAlignment)
    block = _eval(n)
    @test block == Block([
        DateTime(2000, 1, 2) => 7,
        DateTime(2000, 1, 3) => 9,
        DateTime(2000, 1, 4) => 10,
    ])

    # Catch edge-case in which there was a bug.
    @test _eval(TimeDag.add(n2, n3; alignment=TimeDag.LeftAlignment)) == Block([
        DateTime(2000, 1, 2) => 0,
        DateTime(2000, 1, 3) => 1,
        DateTime(2000, 1, 5) => 3,
    ])
    @test _eval(TimeDag.add(n3, n2; alignment=TimeDag.LeftAlignment)) == Block{Int64}()
end

@testset "subtract" begin
    # Union alignment.
    n = n1 - n2
    @test n === TimeDag.subtract(n1, n2; alignment=TimeDag.UnionAlignment)
    block = _eval(n)
    @test block == Block([
        DateTime(2000, 1, 2) => -3,
        DateTime(2000, 1, 3) => -3,
        DateTime(2000, 1, 4) => -2,
        DateTime(2000, 1, 5) => -4,
    ])

    # Intersect alignment.
    n = TimeDag.subtract(n1, n2; alignment=TimeDag.IntersectAlignment)

    @test _eval(n) == Block([
        DateTime(2000, 1, 2) => -3,
        DateTime(2000, 1, 3) => -3,
    ])

    # Left alignment
    n = TimeDag.subtract(n1, n2; alignment=TimeDag.LeftAlignment)
    @test _eval(n) == Block([
        DateTime(2000, 1, 2) => -3,
        DateTime(2000, 1, 3) => -3,
        DateTime(2000, 1, 4) => -2,
    ])

    # Catch edge-case in which there was a bug.
    @test _eval(TimeDag.subtract(n2, n3; alignment=TimeDag.LeftAlignment)) == Block([
        DateTime(2000, 1, 2) => 10,
        DateTime(2000, 1, 3) => 11,
        DateTime(2000, 1, 5) => 13,
    ])
    @test _eval(TimeDag.subtract(n3, n2; alignment=TimeDag.LeftAlignment)) == Block{Int64}()
end
