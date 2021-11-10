@recipe function f(block::Block{<:Real})
    seriestype --> :steppost
    return block.times, block.values
end
