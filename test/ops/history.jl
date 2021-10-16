function _naive_history(block::Block{T}, window::Int) where {T}
    @assert window > 0
    times = DateTime[]
    values = Vector{T}[]
    buffer = CircularBuffer{T}(window)
    for (time, value) in block
        # Push a new value onto the buffer. (If the buffer is full, it will overwrite the
        # value that is falling out of the buffer, because it is circular.)
        push!(buffer, value)
        isfull(buffer) || continue
        push!(times, time)
        push!(values, copy(buffer))
    end
    return Block(times, values)
end

function _test_history(block::Block)
    n_in = block_node(block)
    for window in 1:length(block)
        expected = _naive_history(block, window)
        result = _eval(history(n_in, window))
        @test expected == result
    end
end

@testset "invalid" begin
    @test_throws ArgumentError history(n1, 0)
end

@testset "simple" begin
    _test_history(b3)
    _test_history(b4)
    _test_history(b_boolean)
end

@testset "vector" begin
    _test_history(_get_rand_svec_block(MersenneTwister(42), 3, 10))
    _test_history(_get_rand_vec_block(MersenneTwister(42), 3, 10))
end
