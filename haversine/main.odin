package haversine

import "base:runtime"
import "base:intrinsics"
import "core:log"
import "core:os"
import "core:math"
import "core:strings"
import "core:sys/linux"
import "core:fmt"
import "../common/logger"
import "../common/clock"
import "../common/prof"
import "json"

EARTH_RADIUS :: 6372.8
TEST_COUNT :: 32

Pair :: struct {
	x0, y0: f64,
	x1, y1: f64,
}

main :: proc() {
	context.logger = logger.default

	clock.init()
	prof.init()

	// raw := read_file("pairs.json")
	raw := map_file("pairs.json")

	answer := compute(json.parser(raw))
	// compute_custom_math(json.parser(raw))
	// compute_reference(json.parser(raw))

	// reference_data := read_file("answer")
	reference_data := map_file("answer")
	reference      := (cast(^f64)&reference_data[0])^

	fmt.printf("Answer: %.16f\nReference: %.16f\nDifference: %.16f\n", answer, reference, answer - reference)
}

compute :: proc(p: json.Parser) -> f64 { prof.procedure()
	sqrt :: asm(x: f64) -> (r: f64) [x -> r] {
		sqrtsd r, x
	}

	@(enable_target_feature="fma")
	sin :: proc "contextless" (x: f64) -> f64 {
		x2 := x * x

		r: f64 = transmute(f64)u64(0x3ce883c1c5deffbe)
		r = fma(r, x2, transmute(f64)u64(0xbd6ae43dc9bf8ba7))
		r = fma(r, x2, transmute(f64)u64(0x3de6123ce513b09f))
		r = fma(r, x2, transmute(f64)u64(0xbe5ae6454d960ac4))
		r = fma(r, x2, transmute(f64)u64(0x3ec71de3a52aab96))
		r = fma(r, x2, transmute(f64)u64(0xbf2a01a01a014eb6))
		r = fma(r, x2, transmute(f64)u64(0x3f811111111110c9))
		r = fma(r, x2, transmute(f64)u64(0xbfc5555555555555))
		r = fma(r, x2, 1)
		r *= x

		return r
	}

	@(enable_target_feature="fma")
	asin :: proc "contextless" (x2: f64) -> f64 {
		reduce := x2 > 0.5
		x2     := reduce ? 1 - x2 : x2

		r: f64 = transmute(f64)u64(0x3fedfc53682725ca)
		r = fma(r, x2, transmute(f64)u64(0xc00bec6daf74ed61))
		r = fma(r, x2, transmute(f64)u64(0x4018bf4dadaf548c))
		r = fma(r, x2, transmute(f64)u64(0xc01b06f523e74f33))
		r = fma(r, x2, transmute(f64)u64(0x4014537ddde2d76d))
		r = fma(r, x2, transmute(f64)u64(0xc006067d334b4792))
		r = fma(r, x2, transmute(f64)u64(0x3ff1fb54da575b22))
		r = fma(r, x2, transmute(f64)u64(0xbfd57380bcd2890e))
		r = fma(r, x2, transmute(f64)u64(0x3fb69b370aad086e))
		r = fma(r, x2, transmute(f64)u64(0xbf721438ccc95d62))
		r = fma(r, x2, transmute(f64)u64(0x3f8b8a33b8e380ef))
		r = fma(r, x2, transmute(f64)u64(0x3f8c37061f4e5f55))
		r = fma(r, x2, transmute(f64)u64(0x3f91c875d6c5323d))
		r = fma(r, x2, transmute(f64)u64(0x3f96e88ce94d1149))
		r = fma(r, x2, transmute(f64)u64(0x3f9f1c73443a02f5))
		r = fma(r, x2, transmute(f64)u64(0x3fa6db6db3184756))
		r = fma(r, x2, transmute(f64)u64(0x3fb3333333380df2))
		r = fma(r, x2, transmute(f64)u64(0x3fc555555555531e))
		r = fma(r, x2, transmute(f64)u64(0x3ff0000000000000))
		r *= sqrt(x2)

		return reduce ? math.PI/2 - r : r
	}

	p := p
	json.object(&p)
	json.next_pair(&p)
	json.list(&p)

	sum: f64
	count: int
	for json.next_element(&p) {
		json.object(&p)
		json.next_pair(&p); x0, _ := json.number(&p)
		json.next_pair(&p); y0, _ := json.number(&p)
		json.next_pair(&p); x1, _ := json.number(&p)
		json.next_pair(&p); y1, _ := json.number(&p)
		json.next_pair(&p)

		cos_y0 := sin(fma(y0, y0 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2))
		cos_y1 := sin(fma(y1, y1 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2))

		dx          := abs(x1 - x0)
		dy          := abs(y1 - y0)
		sin_dx_half := sin(fma(dx, dx > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx > 180 ? math.PI : 0))
		sin_dy_half := sin(fma(dy, dy > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy > 180 ? math.PI : 0))

		a      := fma(cos_y0*cos_y1, sin_dx_half*sin_dx_half, sin_dy_half*sin_dy_half)
		c_half := asin(a)

		sum   += c_half
		count += 1
	}
	sum *= 2*EARTH_RADIUS

	return sum / sqrt(f64(count))
}

compute_custom_math :: proc(p: json.Parser) -> f64 { prof.procedure()
	sqrt :: asm(x: f64) -> (r: f64) [x -> r] {
		sqrtsd r, x
	}

	@(enable_target_feature="fma")
	sin :: proc "contextless" (x: f64) -> f64 {
		px := abs(x)
		rx := px > math.PI/2 ? math.PI - px : px
		x2 := rx * rx

	    r: f64 = transmute(f64)u64(0x3ce883c1c5deffbe)
	    r = fma(r, x2, transmute(f64)u64(0xbd6ae43dc9bf8ba7))
	    r = fma(r, x2, transmute(f64)u64(0x3de6123ce513b09f))
	    r = fma(r, x2, transmute(f64)u64(0xbe5ae6454d960ac4))
	    r = fma(r, x2, transmute(f64)u64(0x3ec71de3a52aab96))
	    r = fma(r, x2, transmute(f64)u64(0xbf2a01a01a014eb6))
	    r = fma(r, x2, transmute(f64)u64(0x3f811111111110c9))
	    r = fma(r, x2, transmute(f64)u64(0xbfc5555555555555))
	    r = fma(r, x2, 1)
	    r *= rx

	    return x < 0 ? -r : r
	}

	cos :: proc "contextless" (x: f64) -> f64 {
		return sin(x + math.PI/2)
	}

	@(enable_target_feature="fma")
	asin :: proc "contextless" (x: f64) -> f64 {
		reduce := x > 1/math.SQRT_TWO
		rx := reduce ? sqrt(1 - x*x) : x
		x2 := rx * rx

		r: f64 = transmute(f64)u64(0x3fedfc53682725ca)
	    r = fma(r, x2, transmute(f64)u64(0xc00bec6daf74ed61))
	    r = fma(r, x2, transmute(f64)u64(0x4018bf4dadaf548c))
	    r = fma(r, x2, transmute(f64)u64(0xc01b06f523e74f33))
	    r = fma(r, x2, transmute(f64)u64(0x4014537ddde2d76d))
	    r = fma(r, x2, transmute(f64)u64(0xc006067d334b4792))
	    r = fma(r, x2, transmute(f64)u64(0x3ff1fb54da575b22))
	    r = fma(r, x2, transmute(f64)u64(0xbfd57380bcd2890e))
	    r = fma(r, x2, transmute(f64)u64(0x3fb69b370aad086e))
	    r = fma(r, x2, transmute(f64)u64(0xbf721438ccc95d62))
	    r = fma(r, x2, transmute(f64)u64(0x3f8b8a33b8e380ef))
	    r = fma(r, x2, transmute(f64)u64(0x3f8c37061f4e5f55))
	    r = fma(r, x2, transmute(f64)u64(0x3f91c875d6c5323d))
	    r = fma(r, x2, transmute(f64)u64(0x3f96e88ce94d1149))
	    r = fma(r, x2, transmute(f64)u64(0x3f9f1c73443a02f5))
	    r = fma(r, x2, transmute(f64)u64(0x3fa6db6db3184756))
	    r = fma(r, x2, transmute(f64)u64(0x3fb3333333380df2))
	    r = fma(r, x2, transmute(f64)u64(0x3fc555555555531e))
	    r = fma(r, x2, transmute(f64)u64(0x3ff0000000000000))
	    r *= rx

	    return reduce ? math.PI/2 - r : r
	}

	p := p
	json.object(&p)
	json.next_pair(&p)
	json.list(&p)

	sum: f64
	count: int
	for json.next_element(&p) {
		json.object(&p)
		json.next_pair(&p); x0, _ := json.number(&p)
		json.next_pair(&p); y0, _ := json.number(&p)
		json.next_pair(&p); x1, _ := json.number(&p)
		json.next_pair(&p); y1, _ := json.number(&p)
		json.next_pair(&p)

		dx := math.RAD_PER_DEG * (x1 - x0)

		y0 *= math.RAD_PER_DEG
		y1 *= math.RAD_PER_DEG
		dy := y1 - y0

		a := square(sin(dy/2)) + cos(y0)*cos(y1)*square(sin(dx/2))
		c := 2*asin(sqrt(a))

		sum += EARTH_RADIUS * c
		count += 1
	}

	return sum / sqrt(f64(count))
}

compute_reference :: proc(p: json.Parser) -> f64 { prof.procedure()
	p := p
	json.object(&p)
	json.next_pair(&p)
	json.list(&p)

	sum: f64
	count: int
	for json.next_element(&p) {
		json.object(&p)
		json.next_pair(&p); x0, _ := json.number(&p)
		json.next_pair(&p); y0, _ := json.number(&p)
		json.next_pair(&p); x1, _ := json.number(&p)
		json.next_pair(&p); y1, _ := json.number(&p)
		json.next_pair(&p)

		dx := math.RAD_PER_DEG * (x1 - x0)

		y0 *= math.RAD_PER_DEG
		y1 *= math.RAD_PER_DEG
		dy := y1 - y0

		a := square(math.sin(dy/2)) + math.cos(y0)*math.cos(y1)*square(math.sin(dx/2))
		c := 2*math.asin(math.sqrt(a))

		sum += EARTH_RADIUS * c
		count += 1
	}

	return sum / math.sqrt(f64(count))
}

fma :: intrinsics.fused_mul_add
square :: #force_inline proc "contextless" (x: f64) -> f64 {
	return x * x
}

allocate :: proc(#any_int size: int) -> []byte {
	data, err := linux.mmap(0, uint(size), {.READ, .WRITE}, {.PRIVATE, .ANONYMOUS})
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
