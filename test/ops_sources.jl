@testset "block_node" begin
    # We should identity-map wrapping of the same block.
    x = block_node(b1)
    y = block_node(b1)
    @test x.op == y.op
    @test x == y
    @test x === y

    # Similar blocks that are non-identical shouldn't be identity mapped.
    # TODO Maybe they should? The problem is that we don't want to be doing expensive
    #   comparisons of large blocks for the sake of identity mapping.
    x = block_node(Block{Int64}())
    y = block_node(Block{Int64}())
    @test x.op != y.op
    @test x != y
    @test x !== y
end
