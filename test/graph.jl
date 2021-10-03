# WARNING: These tests interfere with the global graph state, and as such will break any
# Node instances that currently exist.

_test_block() = TimeDag.Block(DateTime(2020, 1, 1):Day(1):DateTime(2020, 1, 5), 1:5)

"""
For tests that care about inspecting the internal graph state, call this first to ensure
that the graph is emptied.
"""
function _reset_global_graph()
    GC.gc()
    graph = TimeDag.global_graph()
    graph.weak_to_ref = Dict()
    return nothing
end

@testset "identity mapping" begin
    _reset_global_graph()

    block = _test_block()
    n1 = TimeDag.block_node(block)
    n2 = TimeDag.block_node(block)

    @test n1 == n2
    @test n1 === n2

    graph = TimeDag.global_graph()
    @test length(graph) == 1

    n3 = TimeDag.lag(n1, 1)
    n4 = TimeDag.lag(n1, 1)
    @test n3 == n4
    @test n3 === n4
    @test length(graph) == 2
end

@testset "weakref" begin
    function _create_and_discard()
        graph = TimeDag.global_graph()
        @test length(graph) == 0
        n1 = TimeDag.block_node(_test_block())
        @test length(graph) == 1
        n2 = TimeDag.lag(n1, 1)
        @test length(graph) == 2
        n3 = TimeDag.lag(n2, 1)
        @test length(graph) == 3
        return nothing
    end

    _reset_global_graph()
    _create_and_discard()
    GC.gc()
    # Manual cleanup invocation required, as otherwise it only occurs when we create a new
    # node.
    TimeDag._cleanup!(TimeDag.global_graph())
    @test isempty(TimeDag.global_graph())
    @test isempty(TimeDag.global_graph().weak_to_ref)
end

@testset "many weakref" begin
    function _create_and_discard()
        count = 1
        start = DateTime(2020)
        block = TimeDag.Block(start:Day(1):(start + Day(count - 1)), 1:count)
        n1 = TimeDag.block_node(block)
        x = n1
        for _ in 1:100
            x += n1
        end
        return nothing
    end

    _reset_global_graph()
    _create_and_discard()
    _create_and_discard()
    GC.gc()
    TimeDag._cleanup!(TimeDag.global_graph())
    @test isempty(TimeDag.global_graph())
    @test isempty(TimeDag.global_graph().weak_to_ref)
end
