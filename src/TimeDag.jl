module TimeDag

using AbstractTrees
using DataStructures
using Dates
using LightGraphs
using PrettyTables
using Tables

include("block.jl")
include("graph.jl")
include("evaluation.jl")

include("constant.jl")  # Constant nodes are special, so we need to know about them first.
include("alignment.jl")

include("ops/arithmetic.jl")
include("ops/lagging.jl")
include("ops/sources.jl")
include("ops/align.jl")

end
