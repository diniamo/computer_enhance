package prof

import "base:runtime"
import "core:sys/llvm"
import "core:time"
import "core:fmt"
import "core:strings"
import "core:os"
import "../clock"

PROFILER_ENABLE :: #config(PROFILER_ENABLE, false)

Timing :: struct {
	next:             ^Timing,

	address:           rawptr,
	label:             string,
	hits:              int,
	depth:             int,
	processed_bytes:   int,
	elapsed_inclusive: u64,
	elapsed_exclusive: u64,
}
Zone :: struct {
	parent: ^Timing,
	start:  u64,
}

MAX_TIMINGS :: 512
TABLE_CAPACITY :: 2 * MAX_TIMINGS

when PROFILER_ENABLE {
	root := Timing{label = "Total"}
	last := &root
	// NOTE: 2x means a maximum load factor of 50%
	timing_table: [2 * MAX_TIMINGS]Timing
	timing_scope := &root
}

hash :: proc(address: rawptr) -> u64 {
	Z :: 0x9E3779B97F4A7C15
	D :: 10
	#assert(1 << D == TABLE_CAPACITY)
	return (u64(uintptr(address)) * Z) >> (64 - D)
}

push :: proc(address: rawptr, label: string, processed_bytes: int) -> Zone {
	when PROFILER_ENABLE {
		timing: ^Timing = ---
		for slot := hash(address);; slot = (slot + 1) % TABLE_CAPACITY {
			timing = &timing_table[slot]
			if timing.address == address {
				break
			} else if timing.address == nil {
				timing.address = address
				timing.label   = label

				last.next = timing
				last = timing

				break
			}
		}

		timing.depth += 1
		timing.processed_bytes += processed_bytes

		parent := timing_scope
		timing_scope = timing

		return {parent, clock.read()}
	} else {
		return {}
	}
}
pop :: proc(zone: Zone) {
	when PROFILER_ENABLE {
		elapsed := clock.read() - zone.start
		timing  := timing_scope

		timing.hits  += 1
		timing.depth -= 1
		if timing.depth == 0 {
			timing.elapsed_inclusive += elapsed
		}
		timing.elapsed_exclusive += elapsed
		zone.parent.elapsed_exclusive -= elapsed

		timing_scope = zone.parent
	}
}

@(deferred_out=done)
init :: #force_no_inline proc() -> u64 {
	return clock.read()
}
done :: proc(start: u64) {
	elapsed := clock.to_ns(clock.read() - start)

	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintln(&builder, "\nTotal:", time.Duration(elapsed))

	when PROFILER_ENABLE {
		timing := root.next
		total  := f64(elapsed)
		for timing := root.next; timing != nil; timing = timing.next {
			fmt.sbprintf(&builder, " %s", timing.label)
			if timing.hits > 1 {
				fmt.sbprintf(&builder, " (%d)", timing.hits)
			}
			strings.write_string(&builder, ": ")
			if timing.elapsed_exclusive < timing.elapsed_inclusive {
				exclusive       := clock.to_ns(timing.elapsed_exclusive)
				exclusive_ratio := f64(exclusive) / total * 100
				fmt.sbprintf(&builder, "%s (%.2f%%) / ", time.Duration(exclusive), exclusive_ratio)
			}
			flat       := clock.to_ns(timing.elapsed_inclusive)
			flat_float := f64(flat)
			flat_ratio := flat_float / total * 100
			fmt.sbprintf(&builder, "%s (%.2f%%)", time.Duration(flat), flat_ratio)
			if timing.processed_bytes > 0 {
				processed_float     := f64(timing.processed_bytes)
				processed_megabytes := processed_float / runtime.Megabyte
				throughput          := processed_float / (runtime.Gigabyte * (flat_float / clock.SECOND))
				fmt.sbprintf(&builder, ", %.2fMiB at %.2fGiB/s", processed_megabytes, throughput)
			}
			strings.write_byte(&builder, '\n')
		}
	}

	os.write(os.stderr, builder.buf[:])
}

@(deferred_out=pop)
scope :: #force_no_inline proc(label: string, #any_int processed_bytes := 0) -> Zone {
	when PROFILER_ENABLE {
		return push(llvm.return_address(0), label, processed_bytes)
	} else {
		return {}
	}
}

@(deferred_out=procedure_defer)
procedure :: #force_no_inline proc(#any_int processed_bytes := 0, loc := #caller_location) -> Zone {
	when PROFILER_ENABLE {
		return push(llvm.return_address(0), loc.procedure, processed_bytes)
	} else {
		return {}
	}
}
procedure_defer :: proc(zone: Zone) {
	pop(zone)
}
