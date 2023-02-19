"""
    SimpleUnary{f,TimeAgnostic,T}

Represents a stateless unary operator that will always emit a value.

The value of the `TimeAgnostic` type parmater is coupled to [`time_agnostic`](@ref).
"""
struct SimpleUnary{f,TimeAgnostic,T} <: UnaryNodeOp{T} end

always_ticks(::SimpleUnary) = true
stateless_operator(::SimpleUnary) = true
time_agnostic(::SimpleUnary{f,false}) where {f} = false
time_agnostic(::SimpleUnary{f,true}) where {f} = true
operator!(::SimpleUnary{f,false}, t, x) where {f} = f(t, x)
operator!(::SimpleUnary{f,true}, x) where {f} = f(x)

"""
    SimpleBinary{f,TimeAgnostic,T,A}

Represents a stateless binary operator that will always emit a value.

The value of the `TimeAgnostic` type parmater is coupled to [`time_agnostic`](@ref).
"""
struct SimpleBinary{f,TimeAgnostic,T,A} <: BinaryNodeOp{T,A} end

always_ticks(::SimpleBinary) = true
stateless_operator(::SimpleBinary) = true
time_agnostic(::SimpleBinary{f,false}) where {f} = false
time_agnostic(::SimpleBinary{f,true}) where {f} = true
operator!(::SimpleBinary{f,false}, t, x, y) where {f} = f(t, x, y)
operator!(::SimpleBinary{f,true}, x, y) where {f} = f(x, y)

"""
    SimpleBinaryUnionInitial{f,TimeAgnostic,T,L,R}

Represents a stateless binary operator that will always emit a value.

The value of the `TimeAgnostic` type parmater is coupled to [`time_agnostic`](@ref).

Unlike [`SimpleBinary`](@ref), this also contains initial values for its parent nodes.
See [Initial values](@ref) for more details.
"""
struct SimpleBinaryUnionInitial{f,TimeAgnostic,T,L,R} <: BinaryNodeOp{T,UnionAlignment}
    initial_l::L
    initial_r::R
end

always_ticks(::SimpleBinaryUnionInitial) = true
stateless_operator(::SimpleBinaryUnionInitial) = true
time_agnostic(::SimpleBinaryUnionInitial{f,false}) where {f} = false
time_agnostic(::SimpleBinaryUnionInitial{f,true}) where {f} = true
operator!(::SimpleBinaryUnionInitial{f,false}, t, x, y) where {f} = f(t, x, y)
operator!(::SimpleBinaryUnionInitial{f,true}, x, y) where {f} = f(x, y)
has_initial_values(::SimpleBinaryUnionInitial) = true
initial_left(op::SimpleBinaryUnionInitial) = op.initial_l
initial_right(op::SimpleBinaryUnionInitial) = op.initial_r

"""
    SimpleBinaryLeftInitial{f,T,R}

Represents a stateless binary operator that will always emit a value.

The value of the `TimeAgnostic` type parmater is coupled to [`time_agnostic`](@ref).

Unlike [`SimpleBinary`](@ref), this also contains initial values for its right parent.
See [Initial values](@ref) for more details.
"""
struct SimpleBinaryLeftInitial{f,TimeAgnostic,T,R} <: BinaryNodeOp{T,LeftAlignment}
    initial_r::R
end

always_ticks(::SimpleBinaryLeftInitial) = true
stateless_operator(::SimpleBinaryLeftInitial) = true
time_agnostic(::SimpleBinaryLeftInitial{f,false}) where {f} = false
time_agnostic(::SimpleBinaryLeftInitial{f,true}) where {f} = true
operator!(::SimpleBinaryLeftInitial{f,false}, t, x, y) where {f} = f(t, x, y)
operator!(::SimpleBinaryLeftInitial{f,true}, x, y) where {f} = f(x, y)
has_initial_values(::SimpleBinaryLeftInitial) = true
initial_right(op::SimpleBinaryLeftInitial) = op.initial_r

"""
    SimpleNary{f,TimeAgnostic,N,T,A}

Represents a stateless `N`ary operator that will always emit a value.

The value of the `TimeAgnostic` type parmater is coupled to [`time_agnostic`](@ref).
"""
struct SimpleNary{f,TimeAgnostic,N,T,A} <: NaryNodeOp{N,T,A} end

always_ticks(::SimpleNary) = true
stateless_operator(::SimpleNary) = true
time_agnostic(::SimpleNary{f,false}) where {f} = false
time_agnostic(::SimpleNary{f,true}) where {f} = true
operator!(::SimpleNary{f,false}, t, values...) where {f} = f(t, values...)
operator!(::SimpleNary{f,true}, values...) where {f} = f(values...)

"""
    SimpleNaryInitial{f,TimeAgnostic,N,T,A,Types}

Represents a stateless binary operator that will always emit a value.

The value of the `TimeAgnostic` type parmater is coupled to [`time_agnostic`](@ref).

Unlike [`SimpleNary`](@ref), this also contains initial values.
See [Initial values](@ref) for more details.
"""
struct SimpleNaryInitial{f,TimeAgnostic,N,T,A,Types} <: NaryNodeOp{N,T,A}
    initial::Types
end

always_ticks(::SimpleNaryInitial) = true
stateless_operator(::SimpleNaryInitial) = true
time_agnostic(::SimpleNaryInitial{f,false}) where {f} = false
time_agnostic(::SimpleNaryInitial{f,true}) where {f} = true
operator!(::SimpleNaryInitial{f,false}, t, values...) where {f} = f(t, values...)
operator!(::SimpleNaryInitial{f,true}, values...) where {f} = f(values...)
has_initial_values(::SimpleNaryInitial) = true
initial_values(op::SimpleNaryInitial) = op.initial

"""
    apply(f::Function, x; out_type=nothing, time_agnostic=true)
    apply(
        f::Function, x, y[, z, ..., alignment=DEFAULT_ALIGNMENT];
        out_type=nothing, time_agnostic=true, initial_values=nothing
    )

Obtain a node with values constructed by applying the pure function `f` to the input values.

Iff `time_agnostic` is `false`, `f` will be passed the time of the current knot as the first
argument, in addition to any values.

With more than one nodal argument, alignment will be performed. In this case, the
`alignment` argument can be specified as one of [`INTERSECT`](@ref), [`LEFT`](@ref) or
[`UNION`](@ref). If unspecified, `DEFAULT_ALIGNMENT` will be used.

Internally this will infer the output type of `f` applied to the arguments, and will also
ensure that subgraph elimination occurs when possible.

If `out_type` is not specified, we attempt to infer the value type of the resulting node
automatically, using [`output_type`](@ref). Alternatively, if `out_type` is given as
anything other than `nothing`, it will be used instead.

If `initial_values` is specified, it should be a tuple of the same length as the number of
node-like arguments passed in. See [Initial values](@ref) for more details.
"""
function apply(
    f::Function, x; out_type::Union{Nothing,Type}=nothing, time_agnostic::Bool=true
)
    x = _ensure_node(x)
    T = if isnothing(out_type)
        arg_types = (value_type(x),)
        arg_types = time_agnostic ? arg_types : (DateTime, arg_types...)
        output_type(f, arg_types...)
    else
        out_type
    end
    return obtain_node((x,), SimpleUnary{f,time_agnostic,T}())
end

function _get_op(f, time_agnostic, T, ::UnionAlignment, l::L, r::R) where {L,R}
    return SimpleBinaryUnionInitial{f,time_agnostic,T,L,R}(l, r)
end
function _get_op(f, time_agnostic, T, ::LeftAlignment, l, r::R) where {R}
    return SimpleBinaryLeftInitial{f,time_agnostic,T,R}(r)
end
function _get_op(f, time_agnostic, T, ::IntersectAlignment, l, r)
    return SimpleBinary{f,time_agnostic,T,IntersectAlignment}()
end

function apply(
    f::Function,
    x,
    y,
    alignment::Alignment;
    out_type::Union{Nothing,Type}=nothing,
    initial_values::Union{Nothing,Tuple{<:Any,<:Any}}=nothing,
    time_agnostic::Bool=true,
)
    x = _ensure_node(x)
    y = _ensure_node(y)
    A = typeof(alignment)
    T = if isnothing(out_type)
        arg_types = (value_type(x), value_type(y))
        arg_types = time_agnostic ? arg_types : (DateTime, arg_types...)
        output_type(f, arg_types...)
    else
        out_type
    end
    op = if isnothing(initial_values)
        SimpleBinary{f,time_agnostic,T,A}()
    else
        initial_l, initial_r = initial_values
        L = value_type(x)
        R = value_type(y)
        isa(initial_l, L) || throw(ArgumentError("$initial_l should be of type $L"))
        isa(initial_r, R) || throw(ArgumentError("$initial_r should be of type $R"))
        _get_op(f, time_agnostic, T, alignment, initial_l, initial_r)
    end
    return obtain_node((x, y), op)
end

function apply(f::Function, x::Node, y::Node; kwargs...)
    return apply(f, x, y, DEFAULT_ALIGNMENT; kwargs...)
end
apply(f::Function, x::Node, y; kwargs...) = apply(f, x, y, DEFAULT_ALIGNMENT; kwargs...)
apply(f::Function, x, y::Node; kwargs...) = apply(f, x, y, DEFAULT_ALIGNMENT; kwargs...)

function apply(
    f::Function,
    x,
    y,
    z,
    rest...;
    out_type::Union{Nothing,Type}=nothing,
    initial_values::Union{Nothing,Tuple{Vararg{Any}}}=nothing,
    time_agnostic::Bool=true,
)
    # The last argument *might* be an alignment. If it isn't, we should use the default
    # alignment.
    args = (x, y, z, rest...)
    head = args[1:(end - 1)]
    tail = last(args)
    args, alignment = if isa(tail, Alignment)
        head, tail
    else
        args, DEFAULT_ALIGNMENT
    end

    inputs = map(_ensure_node, args)
    A = typeof(alignment)
    N = length(inputs)
    input_types = map(value_type, inputs)
    T = if isnothing(out_type)
        arg_types = time_agnostic ? input_types : (DateTime, input_types...)
        output_type(f, arg_types...)
    else
        out_type
    end
    # Note that initial values should always be ignored for intersect alignment, since by
    # definition they will never be used.
    op = if A <: IntersectAlignment || isnothing(initial_values)
        SimpleNary{f,time_agnostic,N,T,A}()
    else
        # Sanity check the initial values.
        Types = Tuple{input_types...}
        if !isa(initial_values, Types)
            throw(ArgumentError("$initial_values should be of type $Types"))
        end
        SimpleNaryInitial{f,time_agnostic,N,T,A,Types}(initial_values)
    end
    return obtain_node(inputs, op)
end

"""
    BCast(f::Function)

Represent a function which should be broadcasted when called.

That is, `BCast{f}(x, y...)` is identical to `f.(x, y...)`.
"""
struct BCast{f} <: Function
    BCast(f::Function) = new{f}()
end
@inline (::BCast{f})(args...; kwargs...) where {f} = f.(args...; kwargs...)

"""
    Wrapped{f}

Represent a function that, when called, will expect its arguments to be nodes and try to
convert them as such.
"""
struct Wrapped{f} <: Function
    time_agnostic::Bool
end
@inline function (wrapped::Wrapped{f})(x, rest...; kwargs...) where {f}
    return apply(f, x, rest...; time_agnostic=wrapped.time_agnostic, kwargs...)
end

# TODO Would we like an identity map? Not important right now, but could be in the future
#   if we allow stateful things?

"""
    wrap(f::Function; time_agnostic=true, value_agnostic=false)

Return a callable object that acts on nodes, and returns a node.

It is assumed that `f` is stateless (this will therefore not work with closures). We also
assume that we will always emit a knot when the alignment semantics say we should — thus `f`
must always return a valid output value.

Iff `time_agnostic` is `false`, `f` will be passed the time of the current knot as the first
argument, followed by the value of every input.

If `value_agnostic` is `true`, no values will be passed to `f`.

If the object is called with more than one node, alignment will be performed.
If an alignment other than the default should be used, provide it as the final argument.

Internally this will call `TimeDag.apply(f, args...; kwargs...)`; see there for further
details.
"""
wrap(f::Function; time_agnostic::Bool=true, value_agnostic::Bool=false) = Wrapped{f}(time_agnostic, value_agnostic)

"""
    wrapb(f::Function; time_agnostic=true)

`wrapb` is like [`wrap`](@ref), however `f` will be broadcasted over all input values.
"""
wrapb(f::Function; time_agnostic::Bool=true) = Wrapped{BCast(f)}(time_agnostic)

"""
    @simple_unary(f)

Define a method `f(::Node)` that will obtain the correct instance of `SimpleUnary{f}`.

This will internally infer the output value, and perform subgraph elimination.
"""
macro simple_unary(f, self_inverse::Bool=false)
    f = esc(f)
    return quote
        """
            $($f)(x::Node)

        Obtain a node with values constructed by applying `$($f)` to each input value.
        """
        $f(x::Node) = apply($f, x)
    end
end

"""
    @simple_unary_self_inverse(f)

Define a method `f(::Node)` that will obtain the correct instance of `SimpleUnary{f}`.

This must ONLY be used if `f(f(x)) == x` for all nodes `x`.

This will internally infer the output value, and perform subgraph elimination.
"""
macro simple_unary_self_inverse(f)
    f = esc(f)
    return quote
        """
            $($f)(x::Node)

        Obtain a node with values constructed by applying `$($f)` to each input value.
        """
        function $f(x::Node)
            # Optimisation: self-inverse
            isa(x.op, SimpleUnary{$f}) && return only(parents(x))
            return apply($f, x)
        end
    end
end

"""
    @simple_binary(f)

Define methods `f(x, y)` that will obtain the correct instance of `SimpleBinary{f}`.

These will internally infer the output value, and perform subgraph elimination.
"""
macro simple_binary(f)
    f = esc(f)
    return quote
        """
            $($f)(x, y[, alignment=DEFAULT_ALIGNMENT; kwargs...])

        Obtain a node with values constructed by applying `$($f)` to the input values.

        An `alignment` can optionally be specified. `x` and `y` should be nodes, or
        constants that can be converted to nodes.

        Other keyword arguments are passed to [`apply`](@ref).
        """
        $f(x, y, alignment::Alignment; kwargs...) = apply($f, x, y, alignment; kwargs...)
        $f(x::Node, y::Node; kwargs...) = $f(x, y, DEFAULT_ALIGNMENT; kwargs...)
        $f(x::Node, y; kwargs...) = $f(x, y, DEFAULT_ALIGNMENT; kwargs...)
        $f(x, y::Node; kwargs...) = $f(x, y, DEFAULT_ALIGNMENT; kwargs...)
    end
end
