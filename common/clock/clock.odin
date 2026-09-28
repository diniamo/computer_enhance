package clock

import "core:log"
import "core:sys/linux"

tsc_shift: u16
tsc_mult:  u32
tsc_and:   u64

init :: proc() {
	event := linux.Perf_Event_Attr{
		type = .HARDWARE,
		size = size_of(linux.Perf_Event_Attr),
		config = {
			sw = .DUMMY
		},
		flags = {.Exclude_Kernel, .Exclude_HV, .Exclude_Idle},
	}
	fd, err := linux.perf_event_open(&event, 0, -1, -1, {.FD_NO_GROUP, .FD_CLOEXEC})
	if err != nil { log.fatal("perf_event_open:", err) }
	defer linux.close(fd)

	raw: rawptr
	raw, err = linux.mmap(0, size_of(linux.Perf_Event_Mmap_Page), {.READ}, {.SHARED}, fd)
	if err != nil { log.fatal("mmap:", err) }
	defer linux.munmap(raw, size_of(linux.Perf_Event_Mmap_Page))

	data := cast(^linux.Perf_Event_Mmap_Page)raw
	tsc_shift = data.time_shift
	tsc_mult  = data.time_mult
	tsc_and   = (1 << data.time_shift) - 1
}

rdtsc :: asm() -> (ts: u64) [ts = %rax] {
	rdtsc
	shl %rdx, 32
	or %rax, %rdx
}

read :: proc "contextless" () -> u64 {
	return rdtsc()
}

to_ns :: proc "contextless" (ts: u64) -> u64 {
	quot := ts >> tsc_shift
	rem  := ts & tsc_and
	return quot * u64(tsc_mult) + ((rem * u64(tsc_mult)) >> tsc_shift)
}
