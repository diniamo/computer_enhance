package haversine

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:math"
import "core:strings"
import "core:sys/linux"
import "logger"
import "prof"
import "json"

Pair :: struct {
	x0, y0: f64,
	x1, y1: f64,
}

main :: proc() {
	context.logger = logger.default

	// test_mov_all_bytes()
	// test_nop_all_bytes()
	// test_cmp_all_bytes()
	// test_dec_all_bytes()
	// test_branch_predictor()
	// test_code_alignment_penalties()
	// test_read_ports()
	// test_write_ports()
	// test_simd_reads()
	// test_rough_cache_sizes()
	// test_memory_alignment_penalties()
	// test_cache_set_entropy_penalties()
	// test_non_temporal_improvements()
	// test_prefetch()
	test_read_and_sum("pairs.json")

	/*
	event_fd, err := linux.perf_event_open(&{
		type = .HARDWARE,
		size = size_of(linux.Perf_Event_Attr),
		config = { hw = .CPU_CYCLES },
		flags = {.Exclude_Kernel, .Exclude_HV, .Exclude_Idle},
	}, 0, -1, -1, {})
	if err != nil { log.fatal("Failed to open event FD:", err) }

	raw: rawptr = ---
	raw, err = linux.mmap(0, size_of(linux.Perf_Event_Mmap_Page), {.READ}, {.SHARED}, event_fd)
	if err != nil { log.fatal("Failed to map perf event page:", err) }

	page := cast(^linux.Perf_Event_Mmap_Page)raw
	if .User_Rdpmc not_in page.cap.flags { log.fatal("Kernel didn't allow rdpmc") }

	// PERF_EVENT_IOC_ENABLE  :: 0x2400
	// PERF_EVENT_IOC_DISABLE :: 0x2401
	// PERF_EVENT_IOC_REFRESH :: 0x2402
	// PERF_EVENT_IOC_RESET   :: 0x2403
	// linux.ioctl(event_fd, PERF_EVENT_IOC_RESET, 0)
	// linux.ioctl(event_fd, PERF_EVENT_IOC_ENABLE, 0)

	barrier :: asm() [#clobber memory] {}
	rdpmc :: asm(counter: u32) -> (value: u64) [
		counter = %ecx,
		value   = %rdx,
	] {
		rdpmc
		shl %rdx, 32
		or %rdx, %rax
	}
	read_counter :: proc(page: ^linux.Perf_Event_Mmap_Page) -> u64 {
		for {
			lock := page.lock
			barrier()

			index := page.index
			value := rdpmc(index - 1)

			barrier()
			if page.lock == lock {
				return value
			}
		}
	}

	overhead := max(u64)
	for i in 0..<10 {
		start := read_counter(page)
		end   := read_counter(page)
		delta := end - start

		overhead = min(overhead, delta)
	}
	*/

	/*
	{ // mov
		start := read_counter(page)
		asm(raw: ^byte, count: uintptr) {
			xor %rax, %rax
		.loop:
			mov [raw + %rax], %al
			inc %rax
			cmp %rax, count
			jb .loop
		}(&data[0], uintptr(len(data)))
		end := read_counter(page)
		cycles := end - start - overhead
		fmt.println("mov:", f64(cycles) / f64(len(data)))
	}

	{ // nop
		start := read_counter(page)
		asm(raw: ^byte, count: uintptr) {
			xor %rax, %rax
		.loop:
			#nop 3
			inc %rax
			cmp %rax, count
			jb .loop
		}(&data[0], uintptr(len(data)))
		end := read_counter(page)
		cycles := end - start - overhead
		fmt.println("nop:", f64(cycles) / f64(len(data)))
	}

	{ // inc
		start := read_counter(page)
		asm(raw: ^byte, count: uintptr) {
			xor %rax, %rax
		.loop:
			inc %rax
			cmp %rax, count
			jb .loop
		}(&data[0], uintptr(len(data)))
		end := read_counter(page)
		cycles := end - start - overhead
		fmt.println("inc:", f64(cycles) / f64(len(data)))
	}

	{ // dec
		start := read_counter(page)
		asm(raw: ^byte, count: uintptr) {
		.loop:
			dec count
			jnz .loop
		}(&data[0], uintptr(len(data)))
		end := read_counter(page)
		cycles := end - start - overhead
		fmt.println("dec:", f64(cycles) / f64(len(data)))
	}
	*/

	// linux.ioctl(event_fd, PERF_EVENT_IOC_DISABLE, 0)

	// data: [8]byte
	// linux.read(event_fd, data[:])
	// cycles := transmute(u64)data
	// fmt.println(cycles)

	// test_os_read("pairs.json")
	// test_fault_behavior()
	// test_mapped_read("pairs.json")

	// routine()
}

routine :: proc() { prof.init()
	// raw := read_file("pairs.json")
	raw := map_file("pairs.json")

	document := json.parse_data(raw, context.temp_allocator)
	data := document.(map[string]json.Value)

	pairs := extract_pairs(data["pairs"], context.temp_allocator)
	sum   := compute_pairs(pairs)
	count := len(pairs)

	// reference_data := read_file("answer")
	reference_data := map_file("answer")
	reference      := (cast(^f64)&reference_data[0])^

	answer := sum / math.sqrt(f64(count))
	fmt.printf("Answer: %.16f\nReference: %.16f\nDifference: %.16f\n", answer, reference, answer - reference)
}

read_file :: proc(path: string) -> []byte {
	file, err := os.open(path)
	if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
	defer os.close(file)

	size: i64 = ---
	size, err = os.file_size(file)
	if err != nil { log.fatalf("Failed to get the size of %s: %s", path, err) }

	data := allocate(size, populate=true)

	{ prof.scope("read_full", len(data))
		_, err = os.read_full(file, data)
		if err != nil { log.fatalf("Failed to read %s: %s", path, err) }
	}

	return data
}

map_file :: proc(path: string) -> []byte {
	fd, err := linux.open(strings.clone_to_cstring(path, context.temp_allocator), {})
	if err != nil { log.fatalf("Failed to open %s: %s", path, err) }

	stat: linux.Statx = ---
	err = linux.statx(fd, nil, {.EMPTY_PATH}, {.SIZE}, &stat)
	if err != nil { log.fatalf("Failed to stat %s: %s", path, err) }

	data: rawptr = ---
	{ prof.scope("mmap", stat.size)
		data, err = linux.mmap(0, uint(stat.size), {.READ}, {.PRIVATE}, fd)
		if err != nil { log.fatalf("Failed to map %s: %s", path, err) }
	}

	return transmute([]byte)runtime.Raw_Slice{data, int(stat.size)}
}

extract_pairs :: proc(value: json.Value, allocator: runtime.Allocator) -> []Pair { prof.procedure()
	array := value.([]json.Value)
	pairs := make([]Pair, len(array), allocator)

	for value, i in array {
		pair := value.(map[string]json.Value)
		pairs[i] = {
			pair["x0"].(f64),
			pair["y0"].(f64),
			pair["x1"].(f64),
			pair["y1"].(f64),
		}
	}

	return pairs
}

compute_pairs :: proc(pairs: []Pair) -> f64 { prof.procedure(len(pairs) * size_of(Pair))
	sum: f64
	for pair in pairs {
		sum += haversine(pair)
	}
	return sum
}

haversine :: proc(pair: Pair) -> f64 {
	EARTH_RADIUS :: 6372.8

	square :: #force_inline proc "contextless" (v: f64) -> f64 {
		return v * v
	}
	sin  :: math.sin_f64
	cos  :: math.cos_f64
	asin :: math.asin_f64
	sqrt :: math.sqrt_f64

	dx := math.RAD_PER_DEG * (pair.x1 - pair.x0)

	y0 := math.RAD_PER_DEG * pair.y0
	y1 := math.RAD_PER_DEG * pair.y1
	dy := y1 - y0

	a := square(sin(dy/2)) + cos(y0)*cos(y1)*square(sin(dx/2))
	c := 2*asin(sqrt(a))

	return EARTH_RADIUS * c
}
