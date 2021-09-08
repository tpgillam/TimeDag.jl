using Dates
using LightGraphs
using Statistics
using TimeDag
using Test

using TimeDag: Block, Node
using TimeDag: duplicate, evaluate, get_up_to!, start_at, value_type
using TimeDag: block_node, constant, empty_node

include("common.jl")

@testset "TimeDag.jl" begin
    include("block.jl")
    include("graph.jl")
    include("constants.jl")

    @testset "ops" begin
        @testset "arithmetic" begin include("ops_arithmetic.jl") end
        @testset "conditional" begin include("ops_conditional.jl") end
        @testset "window" begin include("ops_window.jl") end
    end
end
