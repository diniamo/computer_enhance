package haversine

import "base:intrinsics"
import "core:math"
import "../common/prof"

fma :: intrinsics.fused_mul_add
sqrt :: intrinsics.sqrt
square :: #force_inline proc(x: f64) -> f64 {
	return x * x
}
escape :: #force_inline proc(x: ^$T) {
	x^ = asm(x: T) -> (r: T) [#volatile, x -> r] {}(x^)
}

sin_core :: #force_inline proc(x: f64) -> f64 {
	x2 := x * x

	r := transmute(f64)u64(0x3ce883c1c5deffbe)
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
sin_core_with_prefix :: #force_inline proc(a, b, c: f64) -> f64 {
	return sin_core(fma(a, b, c))
}
sin :: #force_inline proc(x: f64) -> f64 {
	px := abs(x)
	rx := px > math.PI/2 ? math.PI - px : px
	r  := sin_core(rx)
	return x < 0 ? -r : r
}

cos :: #force_inline proc(x: f64) -> f64 {
	return sin(x + math.PI/2)
}

asin_core :: #force_inline proc(x, x2: f64) -> f64 {
	r := transmute(f64)u64(0x3fedfc53682725ca)
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
	r *= x

	return r
}
asin :: #force_inline proc(x: f64) -> f64 {
	reduce := x > 1/math.SQRT_TWO
	rx := reduce ? sqrt(1 - x*x) : x
	r  := asin_core(rx, rx * rx)
	return reduce ? math.PI/2 - r : r
}
asin_from_squared :: #force_inline proc(x2: f64) -> f64 {
		reduce := x2 > 0.5
		x2     := reduce ? 1 - x2 : x2
		r      := asin_core(sqrt(x2), x2)
		return reduce ? math.PI/2 - r : r
}

compute_reference :: proc(pairs: []Pair) -> f64 { prof.procedure()
	sum: f64
	for pair in pairs {
		dx := math.RAD_PER_DEG * (pair.x1 - pair.x0)

		y0 := math.RAD_PER_DEG * pair.y0
		y1 := math.RAD_PER_DEG * pair.y1
		dy := y1 - y0

		a := square(math.sin(dy/2)) + math.cos(y0)*math.cos(y1)*square(math.sin(dx/2))
		c := 2*math.asin(math.sqrt(a))

		sum += EARTH_RADIUS * c
	}

	return sum / math.sqrt(f64(len(pairs)))
}

compute_custom_math :: proc(pairs: []Pair) -> f64 { prof.procedure()
	sum: f64
	for pair in pairs {
		dx := math.RAD_PER_DEG * (pair.x1 - pair.x0)

		y0 := math.RAD_PER_DEG * pair.y0
		y1 := math.RAD_PER_DEG * pair.y1
		dy := y1 - y0

		a := square(sin(dy/2)) + cos(y0)*cos(y1)*square(sin(dx/2))
		c := 2*asin(sqrt(a))

		sum += EARTH_RADIUS * c
	}

	return sum / sqrt(f64(len(pairs)))
}

compute_simplified :: proc(pairs: []Pair) -> f64 { prof.procedure()
	sum: f64
	for pair in pairs {
		x0, y0, x1, y1 := pair.x0, pair.y0, pair.x1, pair.y1

		cos_y0 := sin_core_with_prefix(y0, y0 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1 := sin_core_with_prefix(y1, y1 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)

		dx          := abs(x1 - x0)
		dy          := abs(y1 - y0)
		sin_dx_half := sin_core_with_prefix(dx, dx > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx > 180 ? math.PI : 0)
		sin_dy_half := sin_core_with_prefix(dy, dy > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy > 180 ? math.PI : 0)

		a      := fma(cos_y0*cos_y1, sin_dx_half*sin_dx_half, sin_dy_half*sin_dy_half)
		c_half := asin_from_squared(a)

		sum += c_half
	}
	sum *= 2*EARTH_RADIUS

	return sum / sqrt(f64(len(pairs)))
}

compute_interleaved_4 :: proc(pairs: []Pair) -> f64 { prof.procedure()
	assert(len(pairs) % 4 == 0)

	sum: f64
	for i := 0; i < len(pairs); i += 4 {
		pair_0 := pairs[i + 0]
		pair_1 := pairs[i + 1]
		pair_2 := pairs[i + 2]
		pair_3 := pairs[i + 3]

		x0_0, y0_0, x1_0, y1_0 := pair_0.x0, pair_0.y0, pair_0.x1, pair_0.y1
		x0_1, y0_1, x1_1, y1_1 := pair_1.x0, pair_1.y0, pair_1.x1, pair_1.y1
		x0_2, y0_2, x1_2, y1_2 := pair_2.x0, pair_2.y0, pair_2.x1, pair_2.y1
		x0_3, y0_3, x1_3, y1_3 := pair_3.x0, pair_3.y0, pair_3.x1, pair_3.y1

		cos_y0_0 := sin_core_with_prefix(y0_0, y0_0 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_1 := sin_core_with_prefix(y0_1, y0_1 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_2 := sin_core_with_prefix(y0_2, y0_2 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_3 := sin_core_with_prefix(y0_3, y0_3 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)

		cos_y1_0 := sin_core_with_prefix(y1_0, y1_0 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_1 := sin_core_with_prefix(y1_1, y1_1 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_2 := sin_core_with_prefix(y1_2, y1_2 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_3 := sin_core_with_prefix(y1_3, y1_3 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)

		dx_0 := abs(x1_0 - x0_0)
		dx_1 := abs(x1_1 - x0_1)
		dx_2 := abs(x1_2 - x0_2)
		dx_3 := abs(x1_3 - x0_3)

		dy_0 := abs(y1_0 - y0_0)
		dy_1 := abs(y1_1 - y0_1)
		dy_2 := abs(y1_2 - y0_2)
		dy_3 := abs(y1_3 - y0_3)

		sin_dx_half_0 := sin_core_with_prefix(dx_0, dx_0 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_0 > 180 ? math.PI : 0)
		sin_dx_half_1 := sin_core_with_prefix(dx_1, dx_1 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_1 > 180 ? math.PI : 0)
		sin_dx_half_2 := sin_core_with_prefix(dx_2, dx_2 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_2 > 180 ? math.PI : 0)
		sin_dx_half_3 := sin_core_with_prefix(dx_3, dx_3 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_3 > 180 ? math.PI : 0)

		sin_dy_half_0 := sin_core_with_prefix(dy_0, dy_0 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_0 > 180 ? math.PI : 0)
		sin_dy_half_1 := sin_core_with_prefix(dy_1, dy_1 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_1 > 180 ? math.PI : 0)
		sin_dy_half_2 := sin_core_with_prefix(dy_2, dy_2 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_2 > 180 ? math.PI : 0)
		sin_dy_half_3 := sin_core_with_prefix(dy_3, dy_3 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_3 > 180 ? math.PI : 0)

		a_0 := fma(cos_y0_0*cos_y1_0, sin_dx_half_0*sin_dx_half_0, sin_dy_half_0*sin_dy_half_0)
		a_1 := fma(cos_y0_1*cos_y1_1, sin_dx_half_1*sin_dx_half_1, sin_dy_half_1*sin_dy_half_1)
		a_2 := fma(cos_y0_2*cos_y1_2, sin_dx_half_2*sin_dx_half_2, sin_dy_half_2*sin_dy_half_2)
		a_3 := fma(cos_y0_3*cos_y1_3, sin_dx_half_3*sin_dx_half_3, sin_dy_half_3*sin_dy_half_3)

		c_half_0 := asin_from_squared(a_0)
		c_half_1 := asin_from_squared(a_1)
		c_half_2 := asin_from_squared(a_2)
		c_half_3 := asin_from_squared(a_3)

		sum += c_half_0 + c_half_1 + c_half_2 + c_half_3
	}
	sum *= 2*EARTH_RADIUS

	return sum / sqrt(f64(len(pairs)))
}

compute_interleaved_8 :: proc(pairs: []Pair) -> f64 { prof.procedure()
	assert(len(pairs) % 8 == 0)

	sum: f64
	for i := 0; i < len(pairs); i += 8 {
		pair_0 := pairs[i + 0]
		pair_1 := pairs[i + 1]
		pair_2 := pairs[i + 2]
		pair_3 := pairs[i + 3]
		pair_4 := pairs[i + 4]
		pair_5 := pairs[i + 5]
		pair_6 := pairs[i + 6]
		pair_7 := pairs[i + 7]

		x0_0, y0_0, x1_0, y1_0 := pair_0.x0, pair_0.y0, pair_0.x1, pair_0.y1
		x0_1, y0_1, x1_1, y1_1 := pair_1.x0, pair_1.y0, pair_1.x1, pair_1.y1
		x0_2, y0_2, x1_2, y1_2 := pair_2.x0, pair_2.y0, pair_2.x1, pair_2.y1
		x0_3, y0_3, x1_3, y1_3 := pair_3.x0, pair_3.y0, pair_3.x1, pair_3.y1
		x0_4, y0_4, x1_4, y1_4 := pair_4.x0, pair_4.y0, pair_4.x1, pair_4.y1
		x0_5, y0_5, x1_5, y1_5 := pair_5.x0, pair_5.y0, pair_5.x1, pair_5.y1
		x0_6, y0_6, x1_6, y1_6 := pair_6.x0, pair_6.y0, pair_6.x1, pair_6.y1
		x0_7, y0_7, x1_7, y1_7 := pair_7.x0, pair_7.y0, pair_7.x1, pair_7.y1

		cos_y0_0 := sin_core_with_prefix(y0_0, y0_0 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_1 := sin_core_with_prefix(y0_1, y0_1 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_2 := sin_core_with_prefix(y0_2, y0_2 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_3 := sin_core_with_prefix(y0_3, y0_3 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_4 := sin_core_with_prefix(y0_4, y0_4 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_5 := sin_core_with_prefix(y0_5, y0_5 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_6 := sin_core_with_prefix(y0_6, y0_6 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y0_7 := sin_core_with_prefix(y0_7, y0_7 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)

		cos_y1_0 := sin_core_with_prefix(y1_0, y1_0 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_1 := sin_core_with_prefix(y1_1, y1_1 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_2 := sin_core_with_prefix(y1_2, y1_2 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_3 := sin_core_with_prefix(y1_3, y1_3 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_4 := sin_core_with_prefix(y1_4, y1_4 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_5 := sin_core_with_prefix(y1_5, y1_5 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_6 := sin_core_with_prefix(y1_6, y1_6 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)
		cos_y1_7 := sin_core_with_prefix(y1_7, y1_7 > 0 ? -math.RAD_PER_DEG : math.RAD_PER_DEG, math.PI/2)

		dx_0 := abs(x1_0 - x0_0)
		dx_1 := abs(x1_1 - x0_1)
		dx_2 := abs(x1_2 - x0_2)
		dx_3 := abs(x1_3 - x0_3)
		dx_4 := abs(x1_4 - x0_4)
		dx_5 := abs(x1_5 - x0_5)
		dx_6 := abs(x1_6 - x0_6)
		dx_7 := abs(x1_7 - x0_7)

		dy_0 := abs(y1_0 - y0_0)
		dy_1 := abs(y1_1 - y0_1)
		dy_2 := abs(y1_2 - y0_2)
		dy_3 := abs(y1_3 - y0_3)
		dy_4 := abs(y1_4 - y0_4)
		dy_5 := abs(y1_5 - y0_5)
		dy_6 := abs(y1_6 - y0_6)
		dy_7 := abs(y1_7 - y0_7)

		sin_dx_half_0 := sin_core_with_prefix(dx_0, dx_0 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_0 > 180 ? math.PI : 0)
		sin_dx_half_1 := sin_core_with_prefix(dx_1, dx_1 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_1 > 180 ? math.PI : 0)
		sin_dx_half_2 := sin_core_with_prefix(dx_2, dx_2 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_2 > 180 ? math.PI : 0)
		sin_dx_half_3 := sin_core_with_prefix(dx_3, dx_3 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_3 > 180 ? math.PI : 0)
		sin_dx_half_4 := sin_core_with_prefix(dx_4, dx_4 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_4 > 180 ? math.PI : 0)
		sin_dx_half_5 := sin_core_with_prefix(dx_5, dx_5 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_5 > 180 ? math.PI : 0)
		sin_dx_half_6 := sin_core_with_prefix(dx_6, dx_6 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_6 > 180 ? math.PI : 0)
		sin_dx_half_7 := sin_core_with_prefix(dx_7, dx_7 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dx_7 > 180 ? math.PI : 0)

		sin_dy_half_0 := sin_core_with_prefix(dy_0, dy_0 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_0 > 180 ? math.PI : 0)
		sin_dy_half_1 := sin_core_with_prefix(dy_1, dy_1 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_1 > 180 ? math.PI : 0)
		sin_dy_half_2 := sin_core_with_prefix(dy_2, dy_2 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_2 > 180 ? math.PI : 0)
		sin_dy_half_3 := sin_core_with_prefix(dy_3, dy_3 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_3 > 180 ? math.PI : 0)
		sin_dy_half_4 := sin_core_with_prefix(dy_4, dy_4 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_4 > 180 ? math.PI : 0)
		sin_dy_half_5 := sin_core_with_prefix(dy_5, dy_5 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_5 > 180 ? math.PI : 0)
		sin_dy_half_6 := sin_core_with_prefix(dy_6, dy_6 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_6 > 180 ? math.PI : 0)
		sin_dy_half_7 := sin_core_with_prefix(dy_7, dy_7 > 180 ? -math.RAD_PER_DEG/2 : math.RAD_PER_DEG/2, dy_7 > 180 ? math.PI : 0)

		a_0 := fma(cos_y0_0*cos_y1_0, sin_dx_half_0*sin_dx_half_0, sin_dy_half_0*sin_dy_half_0)
		a_1 := fma(cos_y0_1*cos_y1_1, sin_dx_half_1*sin_dx_half_1, sin_dy_half_1*sin_dy_half_1)
		a_2 := fma(cos_y0_2*cos_y1_2, sin_dx_half_2*sin_dx_half_2, sin_dy_half_2*sin_dy_half_2)
		a_3 := fma(cos_y0_3*cos_y1_3, sin_dx_half_3*sin_dx_half_3, sin_dy_half_3*sin_dy_half_3)
		a_4 := fma(cos_y0_4*cos_y1_4, sin_dx_half_4*sin_dx_half_4, sin_dy_half_4*sin_dy_half_4)
		a_5 := fma(cos_y0_5*cos_y1_5, sin_dx_half_5*sin_dx_half_5, sin_dy_half_5*sin_dy_half_5)
		a_6 := fma(cos_y0_6*cos_y1_6, sin_dx_half_6*sin_dx_half_6, sin_dy_half_6*sin_dy_half_6)
		a_7 := fma(cos_y0_7*cos_y1_7, sin_dx_half_7*sin_dx_half_7, sin_dy_half_7*sin_dy_half_7)

		c_half_0 := asin_from_squared(a_0)
		c_half_1 := asin_from_squared(a_1)
		c_half_2 := asin_from_squared(a_2)
		c_half_3 := asin_from_squared(a_3)
		c_half_4 := asin_from_squared(a_4)
		c_half_5 := asin_from_squared(a_5)
		c_half_6 := asin_from_squared(a_6)
		c_half_7 := asin_from_squared(a_7)

		sum += c_half_0 + c_half_1 + c_half_2 + c_half_3 + c_half_4 + c_half_5 + c_half_6 + c_half_7
	}
	sum *= 2*EARTH_RADIUS

	return sum / sqrt(f64(len(pairs)))
}
