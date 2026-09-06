package generator

import "core:os"
import "core:fmt"
import "core:strconv"
import "core:math"
import "core:math/rand"

main :: proc() {
	if len(os.args) < 3 {
		fatal("Usage: generator <seed> <count>")
	}

	seed,  _ := strconv.parse_u64(os.args[1], 10)
	count, _ := strconv.parse_u64(os.args[2], 10)

	context.random_generator = rand.xoshiro256_random_generator(&{seed})

	file, err := os.create("pairs.json")
	if err != nil { fatal("Failed to open pairs.json:", err) }

	sum: f64

	fmt.fprint(file, "{\n\t\"pairs\": [\n")
	for _ in 0 ..< count - 1 {
		sum += generate_pair(file, "\t\t{{\"x0\": %.16f, \"y0\": %.16f, \"x1\": %.16f, \"y1\": %.16f},\n")
	}
	sum += generate_pair(file, "\t\t{{\"x0\": %.16f, \"y0\": %.16f, \"x1\": %.16f, \"y1\": %.16f}\n\t]\n}\n")

	// NOTE: using this instead of an average ensures that we don't converge
	// to a specific answer (~10010) even with different seeds, because that
	// would undermi=ne computing a reference answer that we can check against
	// (say there is a bug which only computes half the pairs,
	//  but the answer is still the same, because of the convergence)
	answer := sum / math.sqrt(f64(count))
	raw    := transmute([8]byte)answer

	err = os.write_entire_file("answer", raw[:])
	if err != nil { fatal("Failed to write answer:", err) }
}

generate_pair :: proc(file: ^os.File, format: string) -> f64 {
	x0 := rand.float64_range(-180, 180)
	y0 := rand.float64_range(-90, 90)
	x1 := rand.float64_range(-180, 180)
	y1 := rand.float64_range(-90, 90)

	fmt.fprintf(file, format, x0, y0, x1, y1)

	return haversine(x0, y0, x1, y1)
}

haversine :: proc(x0, y0, x1, y1: f64) -> f64 {
	EARTH_RADIUS :: 6372.8

	square :: #force_inline proc "contextless" (v: f64) -> f64 {
		return v * v
	}
	sin  :: math.sin_f64
	cos  :: math.cos_f64
	asin :: math.asin_f64
	sqrt :: math.sqrt_f64

	dx := math.RAD_PER_DEG * (x1 - x0)

	y0 := math.RAD_PER_DEG * y0
	y1 := math.RAD_PER_DEG * y1
	dy := y1 - y0

	a := square(sin(dy/2)) + cos(y0)*cos(y1)*square(sin(dx/2))
	c := 2*asin(sqrt(a))

	return EARTH_RADIUS * c
}

fatal :: proc(args: ..any) {
	fmt.eprintln(..args)
	os.exit(1)
}
