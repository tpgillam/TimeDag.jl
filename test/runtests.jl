using DataStructures
using Dates
using LightGraphs
using Statistics
using TimeDag
using Test

using TimeDag: Block, Node
using TimeDag: duplicate, evaluate, get_up_to!, start_at, value_type
using TimeDag: block_node, constant, empty_node

include("common.jl")

#! format: off

@testset "TimeDag.jl" begin
    @testset "maybe" begin include("maybe.jl") end
    @testset "block" begin include("block.jl") end
    @testset "graph" begin include("graph.jl") end
    @testset "constants" begin include("constants.jl") end

    @testset "ops" begin
        @testset "align" begin include("ops_align.jl") end
        @testset "arithmetic" begin include("ops_arithmetic.jl") end
        @testset "conditional" begin include("ops_conditional.jl") end
        @testset "lagging" begin include("ops_lagging.jl") end
        @testset "logical" begin include("ops_logical.jl") end
        @testset "window" begin include("ops_window.jl") end
    end
end

#! format: on
