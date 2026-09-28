package haversine

import "base:runtime"
import "core:log"
import "core:strings"
import "core:sys/linux"
import "core:fmt"
import "../common/ga"
import "../common/logger"
import "../common/clock"
import "../common/prof"
import "../common/json"

EARTH_RADIUS :: 6372.8
TEST_COUNT :: 32

Pair :: struct {
	x0, y0: f64,
	x1, y1: f64,
}

Procedure :: struct {
	name: string,
	pointer: proc([]Pair) -> f64,
}

main :: proc() {
	permanent := ga.create()
	scratch   := ga.create()

	context.allocator      = ga.allocator(&permanent)
	context.temp_allocator = ga.allocator(&scratch)
	context.logger         = logger.default

	clock.init()
	prof.init()

	pairs := load_pairs()

	procedures := []Procedure{
		{"reference",   compute_reference},
		// {"custom_math", compute_custom_math},
		{"simplified",  compute_simplified},
		// {"interleaved_4", compute_interleaved_4},
		{"interleaved_8", compute_interleaved_8},
	}
	for procedure in procedures {
		fmt.printfln("%s: %.16f", procedure.name, procedure.pointer(pairs))
	}

	// reference_data := map_file("answer")
	// reference      := (cast(^f64)&reference_data[0])^
}

load_pairs :: proc() -> []Pair { prof.procedure()
	defer free_all(context.temp_allocator)

	raw := map_file("pairs.json")
	defer unmap_file(raw)

	data := json.parse(raw, context.temp_allocator)

	array := data.(map[string]json.Value)["pairs"].([]json.Value)
	pairs := make([]Pair, len(array), context.allocator)
	for value, i in array {
		object := value.(map[string]json.Value)
		pairs[i] = {
			x0 = object["x0"].(f64),
			y0 = object["y0"].(f64),
			x1 = object["x1"].(f64),
			y1 = object["y1"].(f64),
		}
	}

	return pairs
}

allocate :: proc(#any_int size: int) -> []byte {
	data, err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.PRIVATE, .ANONYMOUS})
	if err != nil { log.fatal("mmap", err) }

	return transmute([]byte)runtime.Raw_Slice{data, size}
}

free :: proc(data: []byte) {
	linux.munmap(raw_data(data), len(data))
}

read_file :: proc(path: string) -> []byte { prof.procedure()
	fd, err := linux.open(strings.clone_to_cstring(path, context.temp_allocator), {})
	if err != nil { log.fatal("open:", err) }
	defer linux.close(fd)

	stat: linux.Statx = ---
	err = linux.statx(fd, nil, {.EMPTY_PATH}, {.SIZE}, &stat)
	if err != nil { log.fatal("statx:", err) }

	size := int(stat.size)
	data := allocate(size)

	for read := 0; read < size; {
		n, err := linux.read(fd, data[read:])
		if err != nil { log.fatal("read:", err) }

		read += n
	}

	return data
}

map_file :: proc(path: string) -> []byte { prof.procedure()
	fd, err := linux.open(strings.clone_to_cstring(path, context.temp_allocator), {})
	if err != nil { log.fatal("open:", err) }
	defer linux.close(fd)

	stat: linux.Statx = ---
	err = linux.statx(fd, nil, {.EMPTY_PATH}, {.SIZE}, &stat)
	if err != nil { log.fatal("statx:", err) }

	data: rawptr = ---
	data, err = linux.mmap(0, uint(stat.size), {.READ}, {.PRIVATE, .POPULATE}, fd)
	if err != nil { log.fatal("mmap:", err) }

	return transmute([]byte)runtime.Raw_Slice{data, int(stat.size)}
}

unmap_file :: proc(data: []byte) {
	linux.munmap(raw_data(data), uint(len(data)))
}

test_math_proc :: proc(name: string, custom, reference: proc "contextless" (f64) -> f64, min, max: f64) {
	arg   := min
	step  := (max - min) / (TEST_COUNT - 1)
	error := f64(0)

	for _ in 0..<TEST_COUNT {
		c := custom(arg)
		r := reference(arg)
		d := c - r

		if abs(d) > abs(error) {
			error = d
		}

		arg += step
	}

	log.infof("%s:\t\t%+.24f", name, error)
}
