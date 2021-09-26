_test_block() = TimeDag.Block(DateTime(2020, 1, 1):Day(1):DateTime(2020, 1, 5), 1:5)

"""
For tests that care about inspecting the internal graph state, call this first to ensure
that the graph is emptied.
"""
function _reset_global_graph()
    GC.gc()
    graph = TimeDag.global_graph()
    graph.node_to_vertex = WeakKeyDict()
    graph.vertex_to_ref = Dict()
    graph.graph = SimpleDiGraph()
    graph.dirty = false
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
    @test isempty(TimeDag.global_graph())
end
