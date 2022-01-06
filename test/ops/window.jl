# Gloriously inefficient ways of computing running & rolled quantities.

function _naive_inception_reduce(T, f::Function, block::Block, min_window::Int)
    @assert min_window > 0
    times = DateTime[]
    values = T[]
    buffer = value_type(block)[]
    for (i, (time, value)) in enumerate(block)
        # Push a new value onto the buffer.
        push!(buffer, value)
        if i < min_window
            # We need to wait longer before emitting.
            continue
        end
        push!(times, time)
        push!(values, f(buffer))
    end

    return Block(times, values)
end

function _naive_inception_reduce(
    T, f::Function, block_a::Block, block_b::Block, min_window::Int
)
    @assert min_window > 0
    @assert block_a.times == block_b.times  # Don't attempt to perform alignment
    times = DateTime[]
    values = T[]
    buffer_a = value_type(block_a)[]
    buffer_b = value_type(block_b)[]
    for i in 1:length(block_a)
        time, a = block_a[i]
        _, b = block_b[i]
        # Push new values onto the buffer.
        push!(buffer_a, a)
        push!(buffer_b, b)
        if i < min_window
            # We need to wait longer before emitting.
            continue
        end
        push!(times, time)
        push!(values, f(buffer_a, buffer_b))
    end

    return Block(times, values)
end

function _naive_window_reduce(
    T, f::Function, block::Block, window::Int, emit_early::Bool, min_window::Int
)
    @assert window > 0
    @assert min_window > 0
    times = DateTime[]
    values = T[]
    buffer = CircularBuffer{value_type(block)}(window)
    for (i, (time, value)) in enumerate(block)
        # Push a new value onto the buffer. (If the buffer is full, it will overwrite the
        # value that is falling out of the buffer, because it is circular.)
        push!(buffer, value)
        if !emit_early && !isfull(buffer)
            # The buffer is not full, and we require that it be full for us to emit a knot.
            continue
        end
        if i < min_window
            # We need to wait longer before emitting.
            continue
        end
        push!(times, time)
        push!(values, f(buffer))
    end

    return Block(times, values)
end

function _naive_window_reduce(
    T,
    f::Function,
    block_a::Block,
    block_b::Block,
    window::Int,
    emit_early::Bool,
    min_window::Int,
)
    @assert window > 0
    @assert min_window > 0
    @assert block_a.times == block_b.times  # Don't attempt to perform alignment

    times = DateTime[]
    values = T[]
    buffer_a = CircularBuffer{value_type(block_a)}(window)
    buffer_b = CircularBuffer{value_type(block_b)}(window)
    for i in 1:length(block_a)
        time, value_a = block_a[i]
        _, value_b = block_b[i]
        # Push a new value onto the buffer. (If the buffer is full, it will overwrite the
        # value that is falling out of the buffer, because it is circular.)
        push!(buffer_a, value_a)
        push!(buffer_b, value_b)
        if !emit_early && !isfull(buffer_a)
            @assert !isfull(buffer_b)
            # The buffer is not full, and we require that it be full for us to emit a knot.
            continue
        end
        if i < min_window
            # We need to wait longer before emitting.
            continue
        end
        push!(times, time)
        push!(values, f(buffer_a, buffer_b))
    end

    return Block(times, values)
end

function _test_inception_op(
    T, f_normal::Function, f_timedag::Function=f_normal; min_window=1, block::Block=b4
)
    n_in = block_node(block)
    @test _eval(f_timedag(n_in)) ≈ _naive_inception_reduce(T, f_normal, block, min_window)
end

function _test_binary_inception_op(
    T, f_normal::Function, f_timedag::Function=f_normal; min_window=1
)
    # TODO test other alignments
    # pre-align outputs so the reduction operation is simpler
    na, nb = coalign(n1, n4)
    block_a, block_b = _eval_fast([na, nb])
    @test isapprox(
        _eval(f_timedag(n1, n4)),
        _naive_inception_reduce(T, f_normal, block_a, block_b, min_window);
        nans=true,
    )
end

function _test_window_op(
    T, f_normal::Function, f_timedag::Function=f_normal; min_window=1, block::Block=b4
)
    n_in = block_node(block)
    for window in min_window:(length(block) + 2)
        n = f_timedag(n_in, window)

        block_default = _eval(n)
        block_ee_false = _eval(f_timedag(n_in, window; emit_early=false))
        block_ee_true = _eval(f_timedag(n_in, window; emit_early=true))

        @test isequal(block_default, block_ee_false)
        @test isapprox(
            block_ee_false,
            _naive_window_reduce(T, f_normal, block, window, false, min_window);
            nans=true,
        )
        @test isapprox(
            block_ee_true,
            _naive_window_reduce(T, f_normal, block, window, true, min_window);
            nans=true,
        )
    end
    return nothing
end

function _test_binary_window_op(
    T, f_normal::Function, f_timedag::Function=f_normal; min_window=1
)
    na = n4
    nb = TimeDag.align(n1, n4)
    block_a, block_b = _eval_fast([na, nb])
    for window in min_window:(length(b4) + 2)
        n = f_timedag(n1, n4, window)

        block = _eval(n)
        block_ee_false = _eval(f_timedag(n1, n4, window; emit_early=false))
        block_ee_true = _eval(f_timedag(n1, n4, window; emit_early=true))

        @test isequal(block, block_ee_false)
        @test isapprox(
            block_ee_false,
            _naive_window_reduce(T, f_normal, block_a, block_b, window, false, min_window);
            nans=true,
        )
        @test isapprox(
            block_ee_true,
            _naive_window_reduce(T, f_normal, block_a, block_b, window, true, min_window);
            nans=true,
        )
    end
    return nothing
end

@testset "sum" begin
    @testset "inception" begin
        @test sum(constant(42)) == constant(42)
        _test_inception_op(Int64, sum)
    end

    @testset "window" begin
        _test_window_op(Int64, sum)
    end
end

@testset "prod" begin
    @testset "inception" begin
        @test prod(constant(42)) == constant(42)
        _test_inception_op(Int64, prod)
    end

    @testset "window" begin
        _test_window_op(Int64, prod)
    end
end

@testset "mean" begin
    @testset "inception" begin
        @test mean(constant(42)) == constant(42)
        _test_inception_op(Float64, mean)
    end

    @testset "window" begin
        _test_window_op(Float64, mean)
    end
end

@testset "var" begin
    @testset "inception" begin
        @test_throws ArgumentError var(constant(42.0))
        _test_inception_op(Float64, var; min_window=2)
        _test_inception_op(Float64, partial(var; corrected=false); min_window=2)
        _test_inception_op(Float64, partial(var; corrected=true); min_window=2)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError var(n4, 0)
        @test_throws ArgumentError var(n4, 1)
        @test_throws ArgumentError var(constant(42.0), 2)

        _test_window_op(Float64, var; min_window=2)
        _test_window_op(Float64, partial(var; corrected=false); min_window=2)
        _test_window_op(Float64, partial(var; corrected=true); min_window=2)
    end
end

@testset "std" begin
    @testset "inception" begin
        @test_throws ArgumentError std(constant(42.0))
        _test_inception_op(Float64, std; min_window=2)
        _test_inception_op(Float64, partial(std; corrected=false); min_window=2)
        _test_inception_op(Float64, partial(std; corrected=true); min_window=2)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError std(n4, 0)
        @test_throws ArgumentError std(n4, 1)
        @test_throws ArgumentError std(constant(42.0), 2)

        _test_window_op(Float64, std; min_window=2)
        _test_window_op(Float64, partial(std; corrected=false); min_window=2)
        _test_window_op(Float64, partial(std; corrected=true); min_window=2)
    end
end

@testset "cov" begin
    @testset "inception" begin
        @test_throws ArgumentError cov(constant(42.0), constant(24.0))
        _test_binary_inception_op(Float64, cov; min_window=2)
        _test_binary_inception_op(Float64, partial(cov; corrected=false); min_window=2)
        _test_binary_inception_op(Float64, partial(cov; corrected=true); min_window=2)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError cov(n1, n4, 0)
        @test_throws ArgumentError cov(n1, n4, 1)
        @test_throws ArgumentError cov(constant(42.0), constant(24.0), 2)

        _test_binary_window_op(Float64, cov; min_window=2)
        _test_binary_window_op(Float64, partial(cov; corrected=false); min_window=2)
        _test_binary_window_op(Float64, partial(cov; corrected=true); min_window=2)
    end
end

@testset "cov matrix static" begin
    dim = 3
    n_obs = 20
    block = _get_rand_svec_block(MersenneTwister(42), dim, n_obs)
    T = SMatrix{dim,dim,eltype(value_type(block)),dim * dim}

    @testset "inception" begin
        @test_throws ArgumentError cov(constant(SVector((1.0, 2.0, 3.0))))
        _test_inception_op(T, cov; min_window=2, block)
        _test_inception_op(T, partial(cov; corrected=false); min_window=2, block)
        _test_inception_op(T, partial(cov; corrected=true); min_window=2, block)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError cov(block_node(block), 0)
        @test_throws ArgumentError cov(block_node(block), 1)
        @test_throws ArgumentError cov(constant(SVector((1, 2, 3))), 2)

        _test_window_op(T, cov; min_window=2, block)
        _test_window_op(T, partial(cov; corrected=false); min_window=2, block)
        _test_window_op(T, partial(cov; corrected=true); min_window=2, block)
    end
end

@testset "cov matrix" begin
    dim = 3
    n_obs = 20
    block = _get_rand_vec_block(MersenneTwister(42), dim, n_obs)
    T = Matrix{eltype(value_type(block))}

    @testset "inception" begin
        @test_throws ArgumentError cov(constant([1.0, 2.0, 3.0]))
        _test_inception_op(T, cov; min_window=2, block)
        _test_inception_op(T, partial(cov; corrected=false); min_window=2, block)
        _test_inception_op(T, partial(cov; corrected=true); min_window=2, block)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError cov(block_node(block), 0)
        @test_throws ArgumentError cov(block_node(block), 1)
        @test_throws ArgumentError cov(constant([1, 2, 3]), 2)

        _test_window_op(T, cov; min_window=2, block)
        _test_window_op(T, partial(cov; corrected=false); min_window=2, block)
        _test_window_op(T, partial(cov; corrected=true); min_window=2, block)
    end
end

@testset "cor" begin
    @testset "inception" begin
        @test_throws ArgumentError cor(constant(42.0), constant(24.0))
        _test_binary_inception_op(Float64, cor; min_window=2)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError cor(n1, n4, 0)
        @test_throws ArgumentError cor(n1, n4, 1)
        @test_throws ArgumentError cor(constant(42.0), constant(24.0), 2)

        _test_binary_window_op(Float64, cor; min_window=2)
    end
end

@testset "ema" begin
    n_obs = 20
    block = _get_rand_block(MersenneTwister(42), n_obs)
    n = block_node(block)

    @test_throws ArgumentError ema(n, 0.0)
    @test_throws ArgumentError ema(n, 0)
    @test_throws ArgumentError ema(n, 1.0)
    @test_throws ArgumentError ema(n, 1)

    for alpha in [0.1, 0.5, 0.9]
        # Naive computation.
        weighted_sum = 0.0
        weighted_count = 0.0
        expected_values = Float64[]
        for x in block.values
            weighted_sum = x + (1 - alpha) * weighted_sum
            weighted_count = 1 + (1 - alpha) * weighted_count
            push!(expected_values, weighted_sum / weighted_count)
        end

        @test _eval(ema(n, alpha)) == Block(block.times, expected_values)
    end

    @test ema(n, 0.5) === ema(n, 3)
end
