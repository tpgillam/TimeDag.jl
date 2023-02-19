@testset "equivalence_classes" begin
    @test TimeDag.equivalence_classes(==, [1, 1, 2, 3, 3, 3]) == [[1, 1], [2], [3, 3, 3]]
    @test TimeDag.equivalence_classes(==, (1, 1, 2, 3, 3, 3)) == [[1, 1], [2], [3, 3, 3]]

    @test begin
        TimeDag.equivalence_classes(
            TimeDag._equal_times, [Block{Int64}(), Block{Float32}()]
        ) == [[Block{Int64}()], [Block{Float32}()]]
    end

    @test begin
        TimeDag.equivalence_classes(
            TimeDag._equal_times, (Block{Int64}(), Block{Float32}())
        ) == [[Block{Int64}()], [Block{Float32}()]]
    end
end
