package clock

import "core:sys/posix"
import "core:simd/x86"

tsc_frequency := estimate_tsc_frequency()

read_os_clock :: proc "contextless" () -> u64 {
	ts: posix.timespec = ---
	posix.clock_gettime(.MONOTONIC, &ts)
	return SECOND*u64(ts.tv_sec) + u64(ts.tv_nsec)
}
get_os_frequency :: proc "contextless" () -> u64 {
	return SECOND
}

read_tsc :: x86._rdtsc
estimate_tsc_frequency :: proc "contextless" () -> u64 {
	WAIT :: 100 * MILLISECOND

	cpu_start  := read_tsc()
	os_start   := read_os_clock()
	os_elapsed := u64(0)
	for {
		os_elapsed = read_os_clock() - os_start
		if os_elapsed >= WAIT { break }
	}
	cpu_end     := read_tsc()
	cpu_elapsed := cpu_end - cpu_start

	return cpu_elapsed * get_os_frequency() / os_elapsed
}

read :: proc "contextless" () -> u64 {
	when USE_OS_CLOCK {
		ts: posix.timespec = ---
		posix.clock_gettime(.MONOTONIC, &ts)
		return SECOND*u64(ts.tv_sec) + u64(ts.tv_nsec)
	} else {
		return read_tsc()
	}
}

to_ns :: proc "contextless" (value: u64) -> u64 {
	when USE_OS_CLOCK {
		return value
	} else {
		// NOTE: The multiply overflows if elapsed corresponds to more than a few seconds,
		// so we have to either do the divide first in floating-point or use more bits.
		wall := u128(value) * SECOND / u128(tsc_frequency)
		return u64(wall)
	}
}
