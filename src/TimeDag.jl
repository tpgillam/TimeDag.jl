module TimeDag

using AbstractTrees
using AssociativeWindowAggregation
using Bijections
using DataStructures
using Dates
using LightGraphs
using PrettyTables
using StaticArrays
using Statistics
using Tables
using TeaFiles

include("maybe.jl")

include("core.jl")
include("identity_map.jl")
include("constant.jl")  # Constant nodes are special, so we need to know about them first.

include("output_type.jl")

include("block.jl")
include("graph.jl")
include("evaluation.jl")

include("alignment.jl")

include("ops/core.jl")

include("ops/align.jl")
include("ops/conditional.jl")
include("ops/lagging.jl")
include("ops/simple.jl")
include("ops/sources.jl")
include("ops/window.jl")

end
