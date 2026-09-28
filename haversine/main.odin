package haversine

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:math"
import "core:math/rand"
import "core:strings"
import "core:sys/linux"
import "../common/logger"
import "../common/prof"
import "json"

Pair :: struct {
	x0, y0: f64,
	x1, y1: f64,
}

main :: proc() {
	context.logger = logger.default

	test_math("sin", sin, math.sin_f64, -math.PI, math.PI)
	test_math("cos", cos, math.cos_f64, -math.PI/2, math.PI/2)
	test_math("sqrt", sqrt, math.sqrt_f64, 0, 1)
	test_math("asin", asin, math.asin_f64, 0, 1)

	prof.init()

	raw := read_file("pairs.json")
	// raw := map_file("pairs.json")

	document := json.parse_data(raw, context.temp_allocator)
	data := document.(map[string]json.Value)

	pairs := extract_pairs(data["pairs"], context.temp_allocator)
	sum   := compute_pairs(pairs)
	count := len(pairs)

	reference_data := read_file("answer")
	// reference_data := map_file("answer")
	reference      := (cast(^f64)&reference_data[0])^

	answer := sum / math.sqrt(f64(count))
	fmt.printf("Answer: %.16f\nReference: %.16f\nDifference: %.16f\n", answer, reference, answer - reference)
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

square :: #force_inline proc "contextless" (v: f64) -> f64 {
	return v * v
}

sin :: proc "contextless" (v: f64) -> f64 {
	return 0
}

cos :: proc "contextless" (v: f64) -> f64 {
	return 0
}

sqrt :: proc "contextless" (v: f64) -> f64 {
	return 0
}

asin :: proc "contextless" (v: f64) -> f64 {
	return 0
}

haversine :: proc(pair: Pair) -> f64 {
	EARTH_RADIUS :: 6372.8

	dx := math.RAD_PER_DEG * (pair.x1 - pair.x0)

	y0 := math.RAD_PER_DEG * pair.y0
	y1 := math.RAD_PER_DEG * pair.y1
	dy := y1 - y0

	a := square(sin(dy/2)) + cos(y0)*cos(y1)*square(sin(dx/2))
	c := 2*asin(sqrt(a))

	return EARTH_RADIUS * c
}

allocate :: proc(#any_int size: int) -> []byte {
	data, err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.PRIVATE, .ANONYMOUS, .POPULATE})
	if err != nil { log.fatal("Failed to allocate memory:", err) }

	return transmute([]byte)runtime.Raw_Slice{data, size}
}

free :: proc(data: []byte) {
	linux.munmap(raw_data(data), len(data))
}

read_file :: proc(path: string) -> []byte {
	file, err := os.open(path)
	if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
	defer os.close(file)

	size: i64 = ---
	size, err = os.file_size(file)
	if err != nil { log.fatalf("Failed to get the size of %s: %s", path, err) }

	data := allocate(size)

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

test_math :: proc(name: string, custom, reference: proc "contextless" (f64) -> f64, min, max: f64) {
	TEST_COUNT :: 10
	EPSILON    :: 0.00000001

	for _ in 0..<TEST_COUNT {
		arg := rand.float64_range(min, max)

		c := custom(arg)
		r := reference(arg)
		d := c - r

		if abs(d) > EPSILON {
			log.errorf("%s: result too imprecise (%f)", name, d)
			return
		}
	}
}
