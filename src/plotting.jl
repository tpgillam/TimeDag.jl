@recipe function f(block::Block{<:Union{Missing,Real}})
    seriestype --> :steppost
    ticks --> :native
    return block.times, block.values
end
