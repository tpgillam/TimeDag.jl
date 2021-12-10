@testset "block_node" begin
    # We should identity-map wrapping of the same block.
    x = block_node(b1)
    y = block_node(b1)
    @test x.op == y.op
    @test x == y
    @test x === y

    # Similar blocks that are non-identical should be identity mapped.
    x = block_node(Block{Int64}())
    y = block_node(Block{Int64}())
    @test x.op == y.op
    @test x == y
    @test x === y
end

@testset "iterdates" begin
    @testset "midnight" begin
        n = iterdates()
        @test n === iterdates(Time(0))
        @test value_type(n) == DateTime

        expected_times = collect(_T_START:Day(1):(_T_END - Day(1)))
        @test _eval(n) == Block(expected_times, expected_times)
    end

    @testset "non-midnight" begin
        n = iterdates(Time(1))
        @test n === iterdates(Time(1))
        @test value_type(n) == DateTime

        first = Date(_T_START) + Time(1)
        last = Date(_T_END) - Day(1) + Time(1)
        expected_times = collect(first:Day(1):last)
        @test _eval(n) == Block(expected_times, expected_times)
    end

    @testset "non-UTC" begin
        timezone = tz"America/Chicago"

        n = iterdates(Time(0), timezone)
        @test n === iterdates(Time(0), timezone)
        @test value_type(n) == DateTime

        # Evaluate over a sufficient range to get some DST changes.
        block = _evaluate(n, DateTime(2020), DateTime(2021))
        @test block.times === block.values
        zdts = ZonedDateTime.(block.times, tz"UTC")
        local_time_of_day = Time.(astimezone.(zdts, timezone))
        @test all(local_time_of_day .== Time(0))
    end

    @testset "non-existent time" begin
        timezone = tz"America/Chicago"
        n = iterdates(Time(2), timezone)
        @test_throws NonExistentTimeError _evaluate(n, DateTime(2020), DateTime(2021))
    end
end

@testset "pulse" begin
    @testset "invalid" begin
        @test_throws ArgumentError pulse(Hour(0))
        @test_throws ArgumentError pulse(Hour(-1))
    end

    @testset "1 day" begin
        n = pulse(Hour(24))
        expected_times = collect(_T_START:Day(1):(_T_END - Day(1)))
        @test _eval(n) == Block(expected_times, expected_times)
    end

    @testset "arbitrary" begin
        # By default, our pulses should be aligned with the default epoch, which is the same
        # as Julia's internal epoch.
        epoch = DateTime(0, 1, 1) - Millisecond(Dates.DATETIMEEPOCH)
        @test epoch.instant.periods == Millisecond(0)

        for delta in (Second(3), Minute(10), Hour(2))
            n = pulse(delta)

            # We expect to be aligned to the Julia epoch. Work in terms of milliseconds
            # since this epoch.
            start = _T_START.instant.periods
            remainder = start % Millisecond(delta)

            pulse_start = remainder == Millisecond(0) ? start : start + (delta - remainder)
            expected_times = [epoch + pulse_start]
            while true
                prev_time = last(expected_times)
                next_time = prev_time + delta
                next_time < _T_END || break
                push!(expected_times, next_time)
            end

            @test _eval(n) == Block(expected_times, expected_times)
        end
    end

    @testset "custom epoch" begin
        delta = Minute(10)
        for offset in Minute(0):Minute(30):Minute(Hour(24))
            epoch = _T_START + offset
            n = pulse(delta; epoch)

            rem_ = (_T_START - epoch) % Millisecond(delta)
            pulse_start = rem_ == Millisecond(0) ? _T_START : _T_START + (delta - rem_)
            expected_times = [pulse_start]
            while true
                prev_time = last(expected_times)
                next_time = prev_time + delta
                next_time < _T_END || break
                push!(expected_times, next_time)
            end
        end
    end

    @testset "equivalents" begin
        @test pulse(Hour(1)) === pulse(Hour(1))
        @test pulse(Hour(1)) === pulse(Minute(60))
        @test pulse(Hour(1)) === pulse(Second(60 * 60))
        @test pulse(Hour(1)) === pulse(Millisecond(60 * 60 * 1000))
        @test pulse(Hour(1); epoch=DateTime(2020)) !=
            pulse(Hour(1); epoch=DateTime(2020, 1, 1, 1, 30))
        # Optimising this in the general case is too hard, even though these two nodes
        # ought to be equivalent
        @test pulse(Hour(1); epoch=DateTime(2020)) != pulse(Hour(1); epoch=DateTime(2021))
    end
end

@testset "tea_file" begin
    mktempdir() do prefix
        # Write some basic data to a file, then read it back.
        path = joinpath(prefix, "moo.tea")
        TeaFiles.write(path, b1)

        n = TimeDag.tea_file(path, :value)
        n2 = TimeDag.tea_file(path, :value)

        @test n2 === n
        @test _eval(n) == b1
    end
end
