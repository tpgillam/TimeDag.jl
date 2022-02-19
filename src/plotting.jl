@recipe function f(block::Block{<:Real})
    seriestype --> :steppost
    ticks --> :native
    return block.times, block.values
end
