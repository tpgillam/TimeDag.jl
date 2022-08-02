@testset "right" begin
    _test_binary_op(right, (x, y) -> y)
    @test right(n1, n1) === n1
end

@testset "left" begin
    _test_binary_op(left, (x, y) -> x)
    @test left(n1, n1) === n1
end

@testset "align" begin
    @test _eval(align(n4, n1)) == b1
    @test _eval(align(n1, n4)) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 2,
        DateTime(2000, 1, 3) => 3,
        DateTime(2000, 1, 4) => 4,
        DateTime(2000, 1, 5) => 4,
        DateTime(2000, 1, 6) => 4,
        DateTime(2000, 1, 7) => 4,
    ])
end

@testset "align_once" begin
    @test _eval(align_once(n4, n1)) == b1
    #! format:off
    @test _eval(align_once(n1, n2)) == Block([
        DateTime(2000, 1, 2) => 2,
        DateTime(2000, 1, 3) => 3,
        DateTime(2000, 1, 5) => 4
    ])
    @test _eval(align_once(n3, n2)) == Block([
        DateTime(2000, 1, 2) => 15
    ])
    @test _eval(align_once(n2, n4)) == Block([
        DateTime(2000, 1, 2) => 5,
        DateTime(2000, 1, 3) => 6,
        DateTime(2000, 1, 5) => 8
    ])
    #! format:on
end

@testset "coalign" begin
    @testset "unary" begin
        @test coalign(n4) === n4
        @test coalign(n4; alignment=INTERSECT) === n4
        @test coalign(n4; alignment=LEFT) === n4
        @test coalign(n4; alignment=UNION) === n4
    end

    @testset "binary" begin
        for alignment in (INTERSECT, LEFT, UNION)
            na, nb = coalign(n1, n2; alignment)
            @test _eval(na) == _eval(left(n1, n2, alignment))
            @test _eval(nb) == _eval(right(n1, n2, alignment))
            @test coalign(n1, n1; alignment) === (n1, n1)
        end
    end

    @testset "ternary" begin
        for alignment in (INTERSECT, LEFT, UNION)
            na, nb, nc = coalign(n1, n2, n3; alignment)

            l(x, y) = left(x, y, alignment)
            r(x, y) = right(x, y, alignment)

            @test _eval(na) == _eval(l(n1, l(n2, n3)))
            @test _eval(nb) == _eval(r(n1, l(n2, n3)))
            @test _eval(nc) == _eval(r(n1, r(n2, n3)))

            @test coalign(n1, n1, n1; alignment) === (n1, n1, n1)
        end
    end

    @testset "ordering" begin
        # We don't want to generate new different nodes if we coalign the same nodes in a
        # different order, when alignment is order-independent.
        nodes = [n1, n2, n3]
        for alignment in (INTERSECT, UNION)
            for indices in permutations([1, 2, 3])
                new_nodes = coalign(nodes[indices]...; alignment)
                @test new_nodes === coalign(nodes...; alignment)[indices]
            end
        end

        # For the case of LEFT, the first node must stay in place, but we should be able to
        # permute the order of the others and not change the answer.
        for indices in permutations([1, 2, 3])
            new_nodes = coalign(n4, nodes[indices]...; alignment=LEFT)
            @test new_nodes === coalign(n4, nodes...; alignment=LEFT)[[1; 1 .+ indices]]
        end
    end
end

@testset "first_knot" begin
    @test _eval(first_knot(n4)) == b4[1:1]
    @test _eval(first_knot(n_boolean)) == b_boolean[1:1]
    @test _eval(empty_node(Float64)) == Block{Float64}()
    @test first_knot(constant(42.0)) === constant(42.0)
end

@testset "active_count" begin
    @test _eval(active_count(n1)) == Block([b1.times[1]], [1])
    @test _eval(active_count(n1, n2)) == Block([b1.times[1], b2.times[1]], [1, 2])
    @test _eval(active_count(n1, n2, n3)) == Block([b1.times[1], b2.times[1]], [2, 3])
    @test _eval(active_count(n1, n2, n3, n4)) == Block([b1.times[1], b2.times[1]], [3, 4])

    # Testing for optimisations.
    @test active_count(n1, n2) === active_count(n2, n1)
    @test active_count(n1, n2, n3) === active_count(n2, n1, n3)
    @test active_count(n1, n2, n3) === active_count(n3, n1, n2)
    @test active_count(n1, n2, n3) === active_count(n3, n2, n1)
end

@testset "prepend" begin
    # The second argument should take over as soon as it is available. In the case that both
    # arguments are constants, that is immediately.
    @test prepend(1, 2) === constant(2)
    @test prepend(1, "s") === constant("s")

    # We should promote or widen types where applicable.
    @test value_type(prepend(1, n1)) == Int64
    @test value_type(prepend(1.0, n1)) == Float64
    @test value_type(prepend("s", n1)) == Any
    @test prepend(1, n2) === prepend(constant(1), n2)
    @test prepend(n1, n2) === prepend(n1, n2)

    @test _eval(prepend(42, n1)) == b1
    @test _eval(prepend(42, n2)) == Block([
        DateTime(2000, 1, 1) => 42,
        DateTime(2000, 1, 2) => 5,
        DateTime(2000, 1, 3) => 6,
        DateTime(2000, 1, 5) => 8,
    ])

    @test _eval(prepend(n4, n2)) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 5,
        DateTime(2000, 1, 3) => 6,
        DateTime(2000, 1, 5) => 8,
    ])

    # Checking type-promotion.
    @test _eval(prepend(n_boolean, lag(n2, 2))) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 0,
        DateTime(2000, 1, 3) => 1,
        DateTime(2000, 1, 4) => 1,
        DateTime(2000, 1, 5) => 5,
    ])
end

@testset "throttle" begin
    @test throttle(n4, 1) === n4
    @test _eval(throttle(n4, 2)) == b4[1:2:end]
    @test _eval(throttle(n4, 3)) == b4[1:3:end]
    @test _eval(throttle(n4, 4)) == b4[1:4:end]
end

@testset "count_knots" begin
    _expected_count_knots(b::Block) = Block(b.times, 1:length(b))
    @test count_knots(n1) === count_knots(n1)
    @test _eval(count_knots(42)) == Block([_T_START], [1])
    # Check for optimisation
    @test count_knots(42) === constant(1)
    @test _eval(count_knots(n1)) == _expected_count_knots(b1)
    @test _eval(count_knots(n4)) == _expected_count_knots(b4)
    @test _eval(count_knots(n_boolean)) == _expected_count_knots(b_boolean)
end

@testset "merge" begin
    # Merging a node with itself any number of times should be a no-op.
    @test merge(n1) === n1
    @test merge(n1, n1) === n1
    @test merge(n1, n1, n1) === n1
    @test merge(n1, n1, n1, n1) === n1

    # More generally, if a node appears multiple times, we only need to keep the _last_
    # occurrence.
    @test merge(n2, n1, n2) === merge(n1, n2)
    @test merge(n1, n2, n1, n2) === merge(n1, n2)
    @test merge(n1, n2, n3, n2, n1, n1, n2, n1, n2) === merge(n3, n1, n2)

    # Merging constants should give a constant.
    # NB: the first argument has to be a node, so as to
    merge(constant(1), constant(2)) === constant(2)
    merge(constant(1), constant(2), constant(3)) === constant(3)

    # If the times of the inputs are identically equal, we expect to not
    # allocate a new block in evaluation.
    b_new = Block(b1.times, 2 .* (1:length(b1.times)))
    @test _eval(merge(block_node(b_new), n1)) === b1
    @test _eval(merge(n1, block_node(b_new))) === b_new

    # Some hand-crafted examples:
    @test _eval(merge(n1, n2)) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 5,
        DateTime(2000, 1, 3) => 6,
        DateTime(2000, 1, 4) => 4,
        DateTime(2000, 1, 5) => 8,
    ])
    @test _eval(merge(n1, n2, n3)) == Block([
        DateTime(2000, 1, 1) => 15,
        DateTime(2000, 1, 2) => 5,
        DateTime(2000, 1, 3) => 6,
        DateTime(2000, 1, 4) => 4,
        DateTime(2000, 1, 5) => 8,
    ])
    @test _eval(merge(n4, n1, n2, n3)) == Block([
        DateTime(2000, 1, 1) => 15,
        DateTime(2000, 1, 2) => 5,
        DateTime(2000, 1, 3) => 6,
        DateTime(2000, 1, 4) => 4,
        DateTime(2000, 1, 5) => 8,
        DateTime(2000, 1, 6) => 6,
        DateTime(2000, 1, 7) => 7,
    ])

    # Type promotion.
    @test value_type(merge(n1, n_boolean)) == Int64
    rng = MersenneTwister()
    @test value_type(merge(n1, block_node(_get_rand_block(rng, 3)))) == Float64
    @test value_type(merge(n1, block_node(_get_rand_vec_block(rng, 3, 3)))) == Any
end
