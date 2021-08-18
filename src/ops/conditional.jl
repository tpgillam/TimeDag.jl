struct ZapMissing{T} <: StatelessUnaryNodeOp{T, false} end
function operator(::ZapMissing{T}, x::Union{Missing, T}) where {T}
    return if ismissing(x)
        # FIXME Having to come up with a value here is fragile. Is there a better API?
        (zero(x), false)
    else
        (x, true)
    end
end
function zap_missing(x::Node)
    if !(Missing <: value_type(x))
        # There are provably no missing values in the input, so return the same node.
        return x
    end
    return obtain_node((x,), ZapMissing{nonmissingtype(value_type(x))}())
end
