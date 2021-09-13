b1 = Block([
    DateTime(2000, 1, 1) => 1,
    DateTime(2000, 1, 2) => 2,
    DateTime(2000, 1, 3) => 3,
    DateTime(2000, 1, 4) => 4,
    DateTime(2000, 1, 5) => 5,
    DateTime(2000, 1, 6) => 6,
    DateTime(2000, 1, 7) => 7,
])

n1 = block_node(b1)

_eval(n) = _evaluate(n, DateTime(2000, 1, 1), DateTime(2000, 1, 10))

_mapallvalues(f, block::Block) = Block(block.times, f(block.values))

function _naive_window_reduce(T, f::Function, block::Block, window::Int, emit_early::Bool)
    @assert window > 0
    times = emit_early ? block.times : block.times[window:end]
    values = T[]
    buffer = CircularBuffer{value_type(block)}(window)
    for value in block.values
        # Push a new value onto the buffer. This will overwrite the previous value.
        push!(buffer, value)
        if !emit_early && !isfull(buffer)
            # The buffer is not full, and we require that it be full for us to emit a knot.
            continue
        end
        push!(values, f(buffer))
    end

    return Block(times, values)
end

function _test_window_op(T, f_normal::Function, f_timedag::Function=f_normal)
    node_in = TimeDag.block_node(b1)

    for window in 1:(length(b1) + 2)
        n = f_timedag(node_in, window)
        block = _eval(n)
        block_ee_false = _eval(f_timedag(n1, window; emit_early=false))
        block_ee_true = _eval(f_timedag(n1, window; emit_early=true))
        @test block == block_ee_false

        @test block_ee_false ≈ _naive_window_reduce(T, f_normal, b1, window, false)
        @test block_ee_true ≈ _naive_window_reduce(T, f_normal, b1, window, true)
    end
    return nothing
end

@testset "sum" begin
    @testset "inception" begin
        @test _eval(TimeDag.sum(n1)) == _mapallvalues(cumsum, b1)
    end

    @testset "window" begin
        _test_window_op(Int64, sum)
    end
end

@testset "prod" begin
    @testset "inception" begin
        @test _eval(TimeDag.prod(n1)) == _mapallvalues(cumprod, b1)
    end

    @testset "window" begin
        _test_window_op(Int64, prod)
    end
end

"""Simple implementation of mean-from-inception, suitable for testing purposes."""
function _inception_mean(values)
    return [x / i for (i, x) in enumerate(cumsum(values))]
end

@testset "mean" begin
    @testset "inception" begin
        @test _eval(TimeDag.mean(n1)) == _mapallvalues(_inception_mean, b1)
    end

    @testset "window" begin
        _test_window_op(Float64, mean)
    end
end
