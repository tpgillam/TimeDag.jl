@testset "block" begin
    @testset "basic" begin
        times = DateTime(2020, 1, 1):Day(1):DateTime(2020, 1, 5)
        values = 1:length(times)

        block = TimeDag.Block(times, values)
        @test TimeDag.value_type(block) == Int64
        @test length(block) == 5
        @test first(block) == (DateTime(2020, 1, 1), 1)
        @test last(block) == (DateTime(2020, 1, 5), 5)
        @test block[1] == first(block)
        @test block[2] == (DateTime(2020, 1, 2), 2)
        @test block[5] == last(block)
        @test collect(block) == collect(zip(times, values))

        # Slicing follows open-closed interval semantics.
        block_slice = TimeDag._slice(block, DateTime(2020, 1, 1), DateTime(2020, 1, 3))
        @test TimeDag.value_type(block_slice) == Int64
        @test length(block_slice) == 2
        @test first(block_slice) == (DateTime(2020, 1, 1), 1)
        @test last(block_slice) == (DateTime(2020, 1, 2), 2)
        @test block_slice[1] == first(block_slice)
        @test block_slice[2] == last(block_slice)
        @test collect(block_slice) == collect(zip(times[1:2], values[1:2]))
    end
end
