struct ZapMissing{T} <: UnaryNodeOp{T} end

stateless(::ZapMissing) = true
time_agnostic(::ZapMissing) = true

function operator!(::ZapMissing{T}, x::Union{Missing,T}) where {T}
    return if ismissing(x)
        Maybe{T}()
    else
        Maybe(x)
    end
end

"""
    zap_missing(x::Node)

Obtain a node which ticks with the values of `x`, so long as that value is not `missing`.

The [`value_type`](@ref) of the node that is returned will always be the `nonmissingtype` of
the `value_type` of `x`.

In the case that `x` cannot tick with `missing` (based on its `value_type`), we just return
`x`.
"""
function zap_missing(x::Node)
    if !(Missing <: value_type(x))
        # There are provably no missing values in the input, so return the same node.
        return x
    end
    return obtain_node((x,), ZapMissing{nonmissingtype(value_type(x))}())
end
