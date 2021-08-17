using Dates
using LightGraphs
using TimeDag
using Test

using TimeDag: Block, Node, block_node, constant, duplicate, get_up_to!, evaluate, start_at

include("common.jl")

@testset "TimeDag.jl" begin
    include("block.jl")
    include("graph.jl")
    include("constants.jl")

    @testset "ops" begin
        include("ops_arithmetic.jl")
    end
end
