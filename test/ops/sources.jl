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

@testset "iterdates" begin
    @testset "midnight" begin
        n = iterdates()
        @test n === iterdates(Time(0))
        @test value_type(n) == DateTime

        expected_times = collect(_T_START:Day(1):(_T_END - Day(1)))
        @test _eval(n) == Block(expected_times, expected_times)
    end

    @testset "non-midnight" begin
        n = iterdates(Time(1))
        @test n === iterdates(Time(1))
        @test value_type(n) == DateTime

        first = Date(_T_START) + Time(1)
        last = Date(_T_END) - Day(1) + Time(1)
        expected_times = collect(first:Day(1):last)
        @test _eval(n) == Block(expected_times, expected_times)
    end
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
