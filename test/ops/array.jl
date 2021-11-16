#! format: off
block_vec = Block([
    _T_START + Day(1) => [11, 12],
    _T_START + Day(2) => [21, 22],
    _T_START + Day(3) => [31, 32],
])

block_mat = Block([
    _T_START + Day(1) => [11 12; 111 112],
    _T_START + Day(2) => [21 22; 211 212],
    _T_START + Day(3) => [31 32; 311 312],
])

block_tup = Block([
    _T_START + Day(1) => (11, 12),
    _T_START + Day(2) => (21, 22),
    _T_START + Day(3) => (31, 32),
])

block_dict = Block([
    _T_START + Day(1) => Dict(:1 => 11, :2 => 12),
    _T_START + Day(2) => Dict(:1 => 21, :2 => 22),
    _T_START + Day(3) => Dict(:1 => 31, :2 => 32),
])

@testset "getindex" begin
    @testset "vector" begin
        n = block_node(block_vec)

        @test value_type(getindex(n, 1)) == Int64
        @test getindex(n, 1) === getindex(n, 1)
        @test getindex(n, 1) === n[1]

        @test _eval(n[1]) == Block([
            _T_START + Day(1) => 11,
            _T_START + Day(2) => 21,
            _T_START + Day(3) => 31,
        ])

        @test _eval(n[2]) == Block([
            _T_START + Day(1) => 12,
            _T_START + Day(2) => 22,
            _T_START + Day(3) => 32,
        ])

        @test getindex(n, :) === n[:]
        @test n[:] === n
    end

    @testset "matrix" begin
        n = block_node(block_mat)

        @test value_type(getindex(n, 1)) == Int64
        @test getindex(n, 1) === getindex(n, 1)
        @test getindex(n, 1) === n[1]

        @test _eval(n[1]) == Block([
            _T_START + Day(1) => 11,
            _T_START + Day(2) => 21,
            _T_START + Day(3) => 31,
        ])

        @test _eval(n[2]) == Block([
            _T_START + Day(1) => 111,
            _T_START + Day(2) => 211,
            _T_START + Day(3) => 311,
        ])

        @test value_type(getindex(n, 1, 2)) == Int64
        @test getindex(n, 1, 2) === getindex(n, 1, 2)
        @test getindex(n, 1, 2) === n[1, 2]

        @test _eval(n[1, 2]) == Block([
            _T_START + Day(1) => 12,
            _T_START + Day(2) => 22,
            _T_START + Day(3) => 32,
        ])

        @test value_type(getindex(n, 1, :)) == Vector{Int64}
        @test getindex(n, 1, :) === getindex(n, 1, :)
        @test getindex(n, 1, :) === n[1, :]

        @test _eval(n[1, :]) == Block([
            _T_START + Day(1) => [11, 12],
            _T_START + Day(2) => [21, 22],
            _T_START + Day(3) => [31, 32],
        ])
    end

    @testset "tuple" begin
        n = block_node(block_tup)

        @test value_type(getindex(n, 1)) == Int64
        @test getindex(n, 1) === getindex(n, 1)
        @test getindex(n, 1) === n[1]

        @test _eval(n[1]) == Block([
            _T_START + Day(1) => 11,
            _T_START + Day(2) => 21,
            _T_START + Day(3) => 31,
        ])

        @test getindex(n, :) === n[:]
        @test n[:] === n
    end

    @testset "dict" begin
        n = block_node(block_dict)

        @test value_type(getindex(n, :1)) == Int64
        @test getindex(n, :1) === getindex(n, :1)
        @test getindex(n, :1) === n[:1]

        @test _eval(n[:1]) == Block([
            _T_START + Day(1) => 11,
            _T_START + Day(2) => 21,
            _T_START + Day(3) => 31,
        ])
    end
end

@testset "vec" begin
    n = block_node(block_vec)
    @test vec(n) === n

    n = block_node(block_mat)
    @test vec(n) === vec(n)
    @test value_type(vec(n)) == Vector{Int64}

    @test _eval(vec(n)) == Block([
        _T_START + Day(1) => [11, 111, 12, 112],
        _T_START + Day(2) => [21, 211, 22, 212],
        _T_START + Day(3) => [31, 311, 32, 312],
    ])
end

#! format: on
