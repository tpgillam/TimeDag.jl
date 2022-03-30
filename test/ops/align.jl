@testset "right" begin
    _test_binary_op(TimeDag.right, (x, y) -> y)
end

@testset "left" begin
    _test_binary_op(TimeDag.left, (x, y) -> x)
end

@testset "align" begin
    @test _eval(TimeDag.align(n4, n1)) == b1
    @test _eval(TimeDag.align(n1, n4)) == Block([
        DateTime(2000, 1, 1) => 1,
        DateTime(2000, 1, 2) => 2,
        DateTime(2000, 1, 3) => 3,
        DateTime(2000, 1, 4) => 4,
        DateTime(2000, 1, 5) => 4,
        DateTime(2000, 1, 6) => 4,
        DateTime(2000, 1, 7) => 4,
    ])
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

@testset "throttle" begin
    @test throttle(n4, 1) === n4
    @test _eval(throttle(n4, 2)) == b4[1:2:end]
    @test _eval(throttle(n4, 3)) == b4[1:3:end]
    @test _eval(throttle(n4, 4)) == b4[1:4:end]
end
