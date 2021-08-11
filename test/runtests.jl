using Dates
using LightGraphs
using TimeDag
using Test

@testset "TimeDag.jl" begin
    include("block.jl")
    include("graph.jl")
end
