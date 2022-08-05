using AssociativeWindowAggregation
using Combinatorics
using DataFrames
using DataStructures
using Dates
using Distributions
using LightGraphs
using LinearAlgebra
using Random
using StaticArrays
using Statistics
using TeaFiles
using Test
using TimeDag
using TimeZones

using TimeDag: Node
using TimeDag: IntersectAlignment, LeftAlignment, UnionAlignment
using TimeDag: duplicate, evaluate_until!, start_at

#! format: off

@testset "TimeDag.jl" begin
    # Perform these tests first, because they do naughty things to the global identity map
    # which would e.g. break nodes defined in common.jl.
    @testset "identity map" begin include("identity_map.jl") end

    include("common.jl")

    # @testset "block" begin include("block.jl") end
    # @testset "constant" begin include("constant.jl") end
    # @testset "empty" begin include("empty.jl") end
    # @testset "maybe" begin include("maybe.jl") end
    # @testset "output_type" begin include("output_type.jl") end

    @testset "ops" begin
        # @testset "align" begin include("ops/align.jl") end
        # @testset "array" begin include("ops/array.jl") end
        # @testset "common" begin include("ops/common.jl") end
        # @testset "conditional" begin include("ops/conditional.jl") end
        # @testset "history" begin include("ops/history.jl") end
        # @testset "lagging" begin include("ops/lagging.jl") end
        @testset "random" begin include("ops/random.jl") end
        # @testset "simple" begin include("ops/simple.jl") end
        # @testset "sources" begin include("ops/sources.jl") end
        # @testset "window" begin include("ops/window.jl") end
    end
end

#! format: on
