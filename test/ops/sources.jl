@testset "block_node" begin
    # We should identity-map wrapping of the same block.
    x = block_node(b1)
    y = block_node(b1)
    @test x.op == y.op
    @test x == y
    @test x === y

    # Similar blocks that are non-identical should be identity mapped.
    x = block_node(Block{Int64}())
    y = block_node(Block{Int64}())
    @test x.op == y.op
    @test x == y
    @test x === y
end

@testset "tea_file" begin
    mktempdir() do prefix
        # Write some basic data to a file, then read it back.
        path = joinpath(prefix, "moo.tea")
        TeaFiles.write(path, b1)

        n = TimeDag.tea_file(path, :value)
        n2 = TimeDag.tea_file(path, :value)

        @test n2 === n
        @test _eval(n) == b1
    end
end
