module TimeDag

using AbstractTrees
using AssociativeWindowAggregation
using Bijections
using DataStructures
using Dates
using LightGraphs
using PrettyTables
using RecipesBase
using StaticArrays
using Statistics
using Tables
using TeaFiles

# Types.
export Block
# Singletons.
export INTERSECT, LEFT, UNION
# Node creation.
export wrap, wrapb
# Source nodes.
export block_node, constant, empty_node
# Other nodes.
export align, history, lag, right, left, zap_missing
# Evaluation & other utilities.
export evaluate, value_type

include("maybe.jl")

include("core.jl")
include("identity_map.jl")
include("constant.jl")  # Constant nodes are special, so we need to know about them first.

include("output_type.jl")

include("block.jl")
include("graph.jl")
include("evaluation.jl")
include("plotting.jl")

include("alignment.jl")

include("ops/core.jl")  # This defines macros useful for definition of other nodes.

include("ops/align.jl")
include("ops/conditional.jl")
include("ops/history.jl")
include("ops/lagging.jl")
include("ops/simple.jl")
include("ops/sources.jl")
include("ops/window.jl")

end
