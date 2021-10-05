_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

# Gloriously inefficient way of computing running quantities from inception.
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

function _test_inception_op(
    T, f_normal::Function, f_timedag::Function=f_normal; min_window=1
)
    @test _eval(f_timedag(n4)) ≈ _naive_inception_reduce(T, f_normal, b4, min_window)
end

function _test_window_op(T, f_normal::Function, f_timedag::Function=f_normal; min_window=1)
    for window in min_window:(length(b4) + 2)
        n = f_timedag(n4, window)
        block = _eval(n)
        block_ee_false = _eval(f_timedag(n4, window; emit_early=false))
        block_ee_true = _eval(f_timedag(n4, window; emit_early=true))
        @test block == block_ee_false

        @test block_ee_false ≈
              _naive_window_reduce(T, f_normal, b4, window, false, min_window)
        @test block_ee_true ≈
              _naive_window_reduce(T, f_normal, b4, window, true, min_window)
    end
    return nothing
end

@testset "sum" begin
    @testset "inception" begin
        _test_inception_op(Int64, sum)
    end

    @testset "window" begin
        _test_window_op(Int64, sum)
    end
end

@testset "prod" begin
    @testset "inception" begin
        _test_inception_op(Int64, prod)
    end

    @testset "window" begin
        _test_window_op(Int64, prod)
    end
end

@testset "mean" begin
    @testset "inception" begin
        _test_inception_op(Float64, mean)
    end

    @testset "window" begin
        _test_window_op(Float64, mean)
    end
end

@testset "var" begin
    @testset "inception" begin
        _test_inception_op(Float64, var; min_window=2)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError var(n4, 0)
        @test_throws ArgumentError var(n4, 1)

        _test_window_op(Float64, var; min_window=2)
    end
end

@testset "std" begin
    @testset "inception" begin
        _test_inception_op(Float64, std; min_window=2)
    end

    @testset "window" begin
        # Windows that are too small should trigger an exception when attempting to create
        # the node.
        @test_throws ArgumentError std(n4, 0)
        @test_throws ArgumentError std(n4, 1)

        _test_window_op(Float64, std; min_window=2)
    end
end
