@testset "wrap" begin
    @testset "unary" begin
        f(x) = x + 1
        _test_unary_op(wrap(f), b4, f)
    end

    @testset "binary" begin
        f(x, y) = x + y + 1
        _test_binary_op(wrap(f), f)
    end
end

@testset "wrapb" begin
    rng = MersenneTwister(42)
    @testset "unary" begin
        f(x) = x + 3
        f_broadcast(x) = f.(x)
        _test_unary_op(wrapb(f), _get_rand_vec_block(rng, 3, 10), f_broadcast)
    end

    @testset "binary" begin
        f(x, y) = x + y + 3
        # TODO proper test here with alignment. Generalise _test_binary_op.
        b1 = _get_rand_vec_block(rng, 3, 10)
        b2 = _get_rand_vec_block(rng, 3, 10)
        n = wrapb(f)(block_node(b1), block_node(b2))
        b = _eval(n)

        @test b.times == b1.times
        @test b.values == [f.(x, y) for (x, y) in zip(b1.values, b2.values)]
    end
end
