@testset "wrap" begin
    @testset "unary" begin
        f(x) = x + 1
        _test_unary_op(wrap(f), b4, f)

        g(t, x) = t > _T_START + Day(2) ? x + 1 : x + 2
        _test_unary_op(wrap(g; time_agnostic=false), b4, g; time_agnostic=false)
    end

    @testset "binary" begin
        f(x, y) = x + y + 1
        _test_binary_op(wrap(f), f)

        g(t, x, y) = t > _T_START + Day(2) ? x + y + 1 : x + y + 2
        _test_binary_op(wrap(g; time_agnostic=false), g; time_agnostic=false)
    end

    @testset "ternary" begin
        f(x, y, z) = x + y + 1 - z
        _test_ternary_op(wrap(f), f)

        g(t, x, y, z) = t > _T_START + Day(2) ? x + y + 1 - z : x + y + 2 - z
        _test_ternary_op(wrap(g; time_agnostic=false), g; time_agnostic=false)
    end
end

@testset "wrapb" begin
    ba = _get_rand_vec_block(MersenneTwister(42), 3, 10)
    bb = _get_rand_vec_block(MersenneTwister(43), 3, 10)
    bc = _get_rand_vec_block(MersenneTwister(44), 3, 10)
    bd = _get_rand_vec_block(MersenneTwister(45), 3, 10)

    na = block_node(ba)
    nb = block_node(bb)
    nc = block_node(bc)
    nd = block_node(bd)

    @testset "unary" begin
        f(x) = x + 3
        f_broadcast(x) = f.(x)
        _test_unary_op(wrapb(f), ba, f_broadcast)

        g(t, x) = t > _T_START + Day(2) ? x + 3 : x + 4
        g_broadcast(t, x) = t > _T_START + Day(2) ? x .+ 3 : x .+ 4
        _test_unary_op(wrapb(g; time_agnostic=false), ba, g_broadcast; time_agnostic=false)
    end

    @testset "binary" begin
        f(x, y) = x + y + 3
        # TODO proper test here with alignment. Generalise _test_binary_op.
        n = wrapb(f)(na, nb)
        b = _eval(n)

        @test b.times == ba.times
        @test b.values == [f.(x, y) for (x, y) in zip(ba.values, bb.values)]
    end

    @testset "ternary" begin
        f(x, y, z) = x + y * z + 3
        # TODO proper test here with alignment.
        n = wrapb(f)(na, nb, nc)
        b = _eval(n)

        @test b.times == ba.times
        @test b.values ==
            [f.(x, y, z) for (x, y, z) in zip(ba.values, bb.values, bc.values)]
    end

    @testset "quaternary" begin
        f(x, y, z, w) = x + y * z + 3 - w
        # TODO proper test here with alignment.
        n = wrapb(f)(na, nb, nc, nd)
        b = _eval(n)

        @test b.times == ba.times
        #! format: off
        @test b.values == [
            f.(x, y, z, w)
            for (x, y, z, w) in zip(ba.values, bb.values, bc.values, bd.values)
        ]
        #! format: on
    end
end
