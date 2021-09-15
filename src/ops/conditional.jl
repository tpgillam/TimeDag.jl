struct ZapMissing{T} <: UnaryNodeOp{T} end

create_operator_evaluation_state(::Tuple{Node}, ::ZapMissing) = _EMPTY_NODE_STATE

stateless(::ZapMissing) = true
time_agnostic(::ZapMissing) = true

function operator!(::ZapMissing{T}, out::Ref{T}, x::Union{Missing, T}) where {T}
    return if ismissing(x)
        false
    else
        @inbounds out[] = x
        true
    end

end

function zap_missing(x::Node)
    if !(Missing <: value_type(x))
        # There are provably no missing values in the input, so return the same node.
        return x
    end
    return obtain_node((x,), ZapMissing{nonmissingtype(value_type(x))}())
end
