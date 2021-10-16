using DataFrames
using DataStructures
using Dates
using LightGraphs
using Random
using StaticArrays
using Statistics
using TeaFiles
using Test
using TimeDag

using TimeDag: Block, Node
using TimeDag: IntersectAlignment, LeftAlignment, UnionAlignment
using TimeDag: duplicate, get_up_to!, start_at

#! format: off

@testset "TimeDag.jl" begin
    # Perform these tests first, because they do naughty things to the global identity map
    # which would e.g. break nodes defined in common.jl.
    @testset "identity map" begin include("identity_map.jl") end

    include("common.jl")

    @testset "maybe" begin include("maybe.jl") end
    @testset "block" begin include("block.jl") end
    @testset "constants" begin include("constants.jl") end

    @testset "ops" begin
        @testset "align" begin include("ops/align.jl") end
        @testset "conditional" begin include("ops/conditional.jl") end
        @testset "lagging" begin include("ops/lagging.jl") end
        @testset "simple" begin include("ops/simple.jl") end
        @testset "sources" begin include("ops/sources.jl") end
        @testset "window" begin include("ops/window.jl") end
    end
end

#! format: on
