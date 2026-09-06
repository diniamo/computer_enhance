package repetition_tester

import "base:runtime"
import "core:fmt"
import "core:time"
import "core:sys/linux"
import "../clock"

Tester :: struct {
	label:           string,
	start_timestamp: u64,
	min_duration:    u64,
	min_timestamp:   u64,
	start_faults:    int,
	processed_bytes: int,
	throughput:      f64,
}

TESTER_GRACE_PERIOD :: 3 * clock.SECOND

new :: proc(label: string, #any_int processed_bytes := 0) -> Tester {
	return {
		label           = label,
		min_duration    = max(u64),
		min_timestamp   = clock.read(),
		processed_bytes = processed_bytes,
	}
}

start :: proc(tester: ^Tester) {
	tester.start_faults    = read_fault_counter()
	tester.start_timestamp = clock.read()
}

end :: proc(tester: ^Tester) {
	now     := clock.read()
	elapsed := now - tester.start_timestamp
	if elapsed < tester.min_duration {
		tester.min_duration    = elapsed
		tester.min_timestamp = now

		ns          := clock.to_ns(elapsed)
		page_faults := read_fault_counter() - tester.start_faults

		// NOTE: override the previous line
		fmt.eprintf("\r\e[K%s: %s", tester.label, time.Duration(ns))
		if tester.processed_bytes != 0 {
			tester.throughput = f64(tester.processed_bytes) / (runtime.Gigabyte * (f64(ns) / clock.SECOND))
			fmt.eprintf(", %f GiB/s", tester.throughput)
		}
		if page_faults > 0 {
			rate := f64(tester.processed_bytes) / f64(page_faults)
			fmt.eprintf(", %d faults (%f KiB/fault)", page_faults, rate)
		}
	}
}

@(deferred_in=_scope_defer)
scope :: proc(tester: ^Tester) {
	start(tester)
}
_scope_defer :: proc(tester: ^Tester) {
	end(tester)
}

is_done :: proc(tester: ^Tester) -> bool {
	done := clock.to_ns(clock.read() - tester.min_timestamp) > TESTER_GRACE_PERIOD
	if done { fmt.eprintln() }
	return done
}

read_fault_counter :: proc() -> int {
	usage: linux.RUsage = ---
	linux.getrusage(.THREAD, &usage)
	return usage.minflt_word
}
