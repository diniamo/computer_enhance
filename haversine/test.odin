package haversine

import "base:runtime"
import "core:strings"
import "core:fmt"
import "core:os"
import "core:log"
import "core:sys/linux"
import "core:sys/linux/uring"
import "core:c/libc"
import "core:slice"
import "core:math/rand"
import "core:thread"
import rt "repetition_tester"

TEST_AVX512    :: #config(TEST_AVX512, false)
TEST_DATA_SIZE :: runtime.Gigabyte

allocate :: proc(#any_int size: int, start: uintptr = 0, populate := false) -> []byte {
	flags := linux.Map_Flags{.PRIVATE, .ANONYMOUS}
	if populate { flags += {.POPULATE} }

	data, err := linux.mmap(start, uint(size), {.READ, .WRITE}, flags)
	if err != nil { log.fatal("Failed to allocate memory:", err) }

	return transmute([]byte)runtime.Raw_Slice{data, size}
}

free :: proc(data: []byte) {
	linux.munmap(raw_data(data), len(data))
}

test_os_read :: proc(path: string) {
	size: i64 = ---
	{
		file, err := os.open(path)
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer os.close(file)

		size, err = os.file_size(file)
		if err != nil { log.fatalf("Failed to get the size of %s: %s", path, err) }
	}

	tester := rt.new("os.read_full", size)

	for {
		file, err := os.open(path)
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer os.close(file)

		data := allocate(size, populate=true)
		defer free(data)

		{ rt.scope(&tester)
			_, err = os.read_full(file, data)
			if err != nil { log.fatalf("Failed to read %s: %s", path, err) }
		}

		if rt.is_done(&tester) { return }
	}
}

test_fault_behavior :: proc() {
	PAGE_COUNT :: 4096
	PAGE_SIZE  :: 4096

	size := PAGE_COUNT * PAGE_SIZE
	data := allocate(size)
	defer free(data)

	fmt.println("Page count,Touch count,Fault count,Extra faults")

	fault_base := rt.read_fault_counter()
	for page_idx in 0..<PAGE_COUNT {
		data[page_idx * PAGE_SIZE] = max(byte)

		touch_count := page_idx + 1
		fault_count := rt.read_fault_counter() - fault_base
		extra       := fault_count - touch_count

		fmt.println(PAGE_COUNT, touch_count, fault_count, extra, sep = ",")
	}
}

test_mapped_read :: proc(path: string) {
	path_c := strings.clone_to_cstring(path, context.temp_allocator)

	size: u64 = ---
	{
		fd, err := linux.open(path_c, {})
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer linux.close(fd)

		stat: linux.Statx = ---
		err = linux.statx(fd, nil, {.EMPTY_PATH}, {.SIZE}, &stat)
		if err != nil { log.fatalf("Failed to stat %s: %s", path, err) }

		size = stat.size
	}

	tester := rt.new("mmap", size)
	for {
		fd, err := linux.open(path_c, {})
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer linux.close(fd)

		data: rawptr = ---
		data, err = linux.mmap(0, uint(size), {.READ}, {.PRIVATE, .POPULATE}, fd)
		if err != nil { log.fatalf("Failed to map %s: %s", path, err) }
		defer linux.munmap(data, 0)

		@static sum: byte
		{ rt.scope(&tester)
			for i in 0..<size {
				sum += (cast(^byte)(uintptr(data) + uintptr(i)))^
			}
		}

		if rt.is_done(&tester) { break }
	}
}

test_mov_all_bytes :: proc() {
	data := allocate(TEST_DATA_SIZE, populate=true)
	defer free(data)

	tester := rt.new("mov all bytes", TEST_DATA_SIZE)

	for {
		{ rt.scope(&tester)
			asm(base: ^byte, count: uintptr) {
				xor %rax, %rax
			.loop:
				mov [base + %rax], %al
				inc %rax
				cmp %rax, count
				jb .loop
			}(&data[0], uintptr(len(data)))
		}

		if rt.is_done(&tester) { break }
	}
}

test_nop_all_bytes :: proc() {
	tester := rt.new("nop 3x1 all bytes", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uintptr) [idx: uintptr] {
				xor idx, idx
			.loop:
				#nop 3
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("nop 1x3 all bytes", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uintptr) [idx: uintptr] {
				xor idx, idx
			.loop:
				nop
				nop
				nop
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("nop 1x9 all bytes", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uintptr) [idx: uintptr] {
				xor idx, idx
			.loop:
				nop
				nop
				nop
				nop
				nop
				nop
				nop
				nop
				nop
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}
}

test_cmp_all_bytes :: proc() {
	tester := rt.new("cmp all bytes", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uintptr) [idx: uintptr] {
				xor idx, idx
			.loop:
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}
}

test_dec_all_bytes :: proc() {
	tester := rt.new("dec all bytes", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uintptr) {
			.loop:
				dec count
				jnz .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}
}

test_branch_predictor :: proc() {
	loop :: asm(base: ^byte, count: uintptr) [idx: uintptr, tmp: uint] {
		xor idx, idx
	.loop:
		mov tmp, [base + idx]
		inc idx

		test tmp, 1
		jnz .skip
		nop
	.skip:
		cmp idx, count
		jb .loop
	}

	test :: proc(data: []byte, label: string) {
		tester := rt.new(label, TEST_DATA_SIZE)

		for {
			{ rt.scope(&tester)
				loop(&data[0], uintptr(len(data)))
			}

			if rt.is_done(&tester) { break }
		}
	}

	data := allocate(TEST_DATA_SIZE, populate=true)
	defer free(data)

	for i in 0..<len(data) { data[i] = 0 }
	test(data, "no branches taken")

	for i in 0..<len(data) { data[i] = 1 }
	test(data, "all branches taken")

	for i in 0..<len(data) { data[i] = i % 2 == 0 ? 1 : 0 }
	test(data, "every 2 branches taken")

	for i in 0..<len(data) { data[i] = i % 3 == 0 ? 1 : 0 }
	test(data, "every 3 branches taken")

	for i in 0..<len(data) { data[i] = i % 4 == 0 ? 1 : 0 }
	test(data, "every 4 branches taken")

	for i in 0..<len(data) { data[i] = byte(libc.rand()) }
	test(data, "random (insecure) branches taken")

	linux.getrandom(data, {.RANDOM})
	test(data, "random (secure) branches taken")
}

test_code_alignment_penalties :: proc() {
	tester := rt.new("64 aligned", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uint) [idx: uintptr] {
				xor idx, idx
				#align 64
			.loop:
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1 aligned", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uint) [idx: uintptr] {
				xor idx, idx
				#align 64
				#nop 1
			.loop:
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("56 aligned", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uint) [idx: uintptr] {
				xor idx, idx
				#align 64
				#nop 56
			.loop:
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("57 aligned", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uint) [idx: uintptr] {
				xor idx, idx
				#align 64
				#nop 57
			.loop:
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("63 aligned", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(count: uint) [idx: uintptr] {
				xor idx, idx
				#align 64
				#nop 63
			.loop:
				inc idx
				cmp idx, count
				jb .loop
			}(TEST_DATA_SIZE)
		}

		if rt.is_done(&tester) { break }
	}
}

test_read_ports :: proc() {
	data := allocate(TEST_DATA_SIZE, populate=true)
	defer free(data)

	tester := rt.new("1x1 read", TEST_DATA_SIZE)

	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				#align 64
			.loop:
				mov tmp, [data]
				sub count, 1
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1x2 read", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				#align 64
			.loop:
				mov tmp, [data]
				mov tmp, [data]
				sub count, 2
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1x3 read", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				#align 64
			.loop:
				mov tmp, [data]
				mov tmp, [data]
				mov tmp, [data]
				sub count, 3
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1x4 read", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				#align 64
			.loop:
				mov tmp, [data]
				mov tmp, [data]
				mov tmp, [data]
				mov tmp, [data]
				sub count, 4
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}
}

test_write_ports :: proc() {
	data := allocate(TEST_DATA_SIZE, populate=true)
	defer free(data)

	tester := rt.new("1x1 write", TEST_DATA_SIZE)

	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				mov tmp, 0
				#align 64
			.loop:
				mov [data], tmp
				sub count, 1
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1x2 write", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				mov tmp, 0
				#align 64
			.loop:
				mov [data], tmp
				mov [data + 1], tmp
				sub count, 2
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1x3 write", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				mov tmp, 0
				#align 64
			.loop:
				mov [data], tmp
				mov [data + 1], tmp
				mov [data + 2], tmp
				sub count, 3
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("1x4 write", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: uint] {
				mov tmp, 0
				#align 64
			.loop:
				mov [data], tmp
				mov [data + 1], tmp
				mov [data + 2], tmp
				mov [data + 3], tmp
				sub count, 4
				jnle .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}
}

test_simd_reads :: proc() {
	data := allocate(TEST_DATA_SIZE, populate=true)
	defer free(data)

	tester := rt.new("4x2 read", TEST_DATA_SIZE)

	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: u32] {
				#align 64
			.loop:
				mov tmp, [data]
				mov tmp, [data + 4]
				sub count, 8
				jnbe .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("8x2 read", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: u64] {
				#align 64
			.loop:
				mov tmp, [data]
				mov tmp, [data + 8]
				sub count, 16
				jnbe .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("16x2 read", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: #simd[2]u64] {
				#align 64
			.loop:
				movdqu tmp, [data]
				movdqu tmp, [data + 16]
				sub count, 32
				jnbe .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("32x2 read", TEST_DATA_SIZE)
	for {
		{ rt.scope(&tester)
			asm(data: ^byte, count: uint) [tmp: #simd[4]u64] {
				#align 64
			.loop:
				vmovdqu tmp, [data]
				vmovdqu tmp, [data + 32]
				sub count, 64
				jnbe .loop
			}(&data[0], uint(len(data)))
		}

		if rt.is_done(&tester) { break }
	}

	when TEST_AVX512 {
		tester = rt.new("64x2 read", TEST_DATA_SIZE)
		for {
			{ rt.scope(&tester)
				asm(data: ^byte, count: uint) [tmp: #simd[8]u64] {
					#align 64
				.loop:
					vmovdqu64 tmp, [data]
					vmovdqu64 tmp, [data + 64]
					sub count, 128
					jnbe .loop
				}(&data[0], uint(len(data)))
			}

			if rt.is_done(&tester) { break }
		}
	}
}

test_read_loop :: proc(label: string, base: ^byte, total, region: uint) {
	tester := rt.new(label, total)
	for {
		{ rt.scope(&tester)
			// NOTE: there are this many movs, because there are 3 serially-dependant instructions after and 2 read ports on my Comet Lake CPU.
			// Additionally, 3*2=6 is rounded up to the lowest power of 2 to simplify the test code.
			asm(base: ^byte, mask: uintptr, total: uint) [sink: #simd[4]u64, ptr: ^byte] {
				mov ptr, base
			.loop:
				vmovdqu sink, [ptr + 0*32]
				vmovdqu sink, [ptr + 1*32]
				vmovdqu sink, [ptr + 2*32]
				vmovdqu sink, [ptr + 3*32]
				vmovdqu sink, [ptr + 4*32]
				vmovdqu sink, [ptr + 5*32]
				vmovdqu sink, [ptr + 6*32]
				vmovdqu sink, [ptr + 7*32]

				add ptr, (8*32)
				and ptr, mask
				or  ptr, base

				sub total, (8*32)
				ja .loop
			}(base, uintptr(region - 1), total)
		}

		if rt.is_done(&tester) { break }
	}
}

test_rough_cache_sizes :: proc() {
	data := allocate(runtime.Gigabyte, start=runtime.Gigabyte, populate=true)
	defer free(data)

	for size: uint = 512; size <= uint(len(data)); size <<= 1 {
		label := fmt.tprint(uint(size), "byte region")
		test_read_loop(label, &data[0], runtime.Gigabyte, size)
		free_all(context.temp_allocator)
	}
}

test_memory_alignment_penalties :: proc() {
	data := allocate(runtime.Gigabyte + 1, start=runtime.Gigabyte, populate=true)
	defer free(data)

	test_read_loop("L1 aligned",    &data[0], runtime.Gigabyte, 8*runtime.Kilobyte)
	test_read_loop("L1 misaligned", &data[1], runtime.Gigabyte, 8*runtime.Kilobyte)

	test_read_loop("L2 aligned",    &data[0], runtime.Gigabyte, 128*runtime.Kilobyte)
	test_read_loop("L2 misaligned", &data[1], runtime.Gigabyte, 128*runtime.Kilobyte)

	test_read_loop("L3 aligned",    &data[0], runtime.Gigabyte, 4*runtime.Megabyte)
	test_read_loop("L3 misaligned", &data[1], runtime.Gigabyte, 4*runtime.Megabyte)

	test_read_loop("Memory aligned",    &data[0], runtime.Gigabyte, runtime.Gigabyte)
	test_read_loop("Memory misaligned", &data[1], runtime.Gigabyte, runtime.Gigabyte)
}

test_cache_set_entropy_penalties :: proc() {
	REGION_SIZE :: 128*runtime.Kilobyte
	// NOTE: on my Comet Lake, cache lines are 64 bytes, so 6 bytes are omitted,
	// and the next 6 bytes select the set in the cache.
	POINTER_INCREMENT :: 1 << (6 + 6)

	data := allocate(REGION_SIZE, start=runtime.Gigabyte + REGION_SIZE, populate=true)
	defer free(data)

	test_read_loop("Distributed read", &data[0], runtime.Gigabyte, REGION_SIZE)

	tester := rt.new("same-set read", runtime.Gigabyte)
	for {
		{ rt.scope(&tester)
			asm(base: ^byte, mask: uintptr, total: uint) [sink: #simd[4]u64, ptr: ^byte] {
				mov ptr, base
			.loop:
				vmovdqu sink, [ptr + 0*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 1*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 2*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 3*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 4*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 5*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 6*POINTER_INCREMENT]
				vmovdqu sink, [ptr + 7*POINTER_INCREMENT]

				add ptr, (8*POINTER_INCREMENT)
				and ptr, mask
				or  ptr, base

				sub total, (8*32)
				ja .loop
			}(&data[0], REGION_SIZE - 1, runtime.Gigabyte)
		}

		if rt.is_done(&tester) { break }
	}
}

test_non_temporal_improvements :: proc() {
	DST_SIZE :: 1*runtime.Gigabyte
	SRC_SIZE :: 8*runtime.Kilobyte

	data := allocate(DST_SIZE + SRC_SIZE, start=runtime.Gigabyte, populate=true)
	defer free(data)

	dst := data[:DST_SIZE]
	src := data[DST_SIZE:]

	tester := rt.new("temporal", DST_SIZE)
	for {
		{ rt.scope(&tester)
			asm(dst, src: ^byte, total: uint, src_mask: uintptr) [ptr: ^byte, tmp: #simd[4]u64] {
				mov ptr, src
			.loop:
				vmovdqu tmp, [ptr]

				vmovdqu [dst + 0*32], tmp
				vmovdqu [dst + 1*32], tmp
				vmovdqu [dst + 2*32], tmp
				vmovdqu [dst + 3*32], tmp

				add dst, (4*32)
				add ptr, (4*32)
				and ptr, src_mask
				or  ptr, src

				sub total, (4*32)
				ja .loop
			}(&dst[0], &src[0], DST_SIZE, SRC_SIZE - 1)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("non-temporal", DST_SIZE)
	for {
		{ rt.scope(&tester)
			asm(dst, src: ^byte, total: uint, src_mask: uintptr) [ptr: ^byte, tmp: #simd[4]u64] {
				mov ptr, src
			.loop:
				vmovdqu tmp, [ptr]

				vmovntdq [dst + 0*32], tmp
				vmovntdq [dst + 1*32], tmp
				vmovntdq [dst + 2*32], tmp
				vmovntdq [dst + 3*32], tmp

				add dst, (4*32)
				add ptr, (4*32)
				and ptr, src_mask
				or  ptr, src

				sub total, (4*32)
				ja .loop
			}(&dst[0], &src[0], DST_SIZE, SRC_SIZE - 1)
		}

		if rt.is_done(&tester) { break }
	}
}

test_prefetch :: proc() {
	OUTER_ITERATIONS :: 1024 * 1024
	INNER_ITERATIONS :: 50

	data := allocate(runtime.Gigabyte, start=runtime.Gigabyte, populate=true)
	defer free(data)

	pointers := slice.reinterpret([]rawptr, data)
	for i in 0 ..< len(pointers) { pointers[i] = &pointers[rand.int_max(len(pointers) - 64/8)] }

	tester := rt.new("no prefetch", len(data))
	for {
		{ rt.scope(&tester)
			asm(pointer: rawptr, outer, inner: uint) [left: uint, a: #simd[4]u64, b: #simd[4]u64] {
			.outer:
				vmovdqu a, [pointer]
				vmovdqu b, [pointer + 32]

				mov pointer, [pointer]
				mov left, inner

			.inner:
				vpxor  a, a, b
				vpaddd a, a, b

				dec left
				jnz .inner

				dec outer
				jnz .outer
			}(pointers[0], OUTER_ITERATIONS, INNER_ITERATIONS)
		}

		if rt.is_done(&tester) { break }
	}

	tester = rt.new("prefetch", len(data))
	for {
		{ rt.scope(&tester)
			asm(pointer: rawptr, outer, inner: uint) [left: uint, a: #simd[4]u64, b: #simd[4]u64] {
			.outer:
				vmovdqu a, [pointer]
				vmovdqu b, [pointer + 32]

				mov pointer, [pointer]
				mov left, inner

				prefetcht0 [pointer]

			.inner:
				vpxor  a, a, b
				vpaddd a, a, b

				dec left
				jnz .inner

				dec outer
				jnz .outer
			}(pointers[0], OUTER_ITERATIONS, INNER_ITERATIONS)
		}

		if rt.is_done(&tester) { break }
	}
}

test_read_and_sum :: proc(path: string) {
	test_serial :: proc(path: cstring, file_size, buffer_size: int) -> u64 {
		fd, err := linux.open(path, {.CLOEXEC})
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer linux.close(fd)

		data := allocate(buffer_size, populate=true)
		defer free(data)

		result: u64
		for remaining := file_size; remaining > 0; {
			read_size := min(buffer_size, remaining)
			for read := 0; read < read_size; {
				n, err := linux.read(fd, data[read:])
				if err != nil { log.fatal("Failed to read file:", err) }

				read += n
			}

			numbers := slice.reinterpret([]u64, data[:read_size])
			for n in numbers { result += n }

			remaining -= read_size
		}

		return result
	}
	test_mapped :: proc(path: cstring, file_size: int) -> u64 {
		fd, err := linux.open(path, {})
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer linux.close(fd)

		raw: rawptr = ---
		raw, err = linux.mmap(0, uint(file_size), {.READ}, {.PRIVATE}, fd)
		if err != nil { log.fatal("Failed to map file:", err) }
		defer linux.munmap(raw, uint(file_size))

		length  := file_size / 8
		numbers := transmute([]u64)runtime.Raw_Slice{raw, length}

		result: u64 = 0
		for n in numbers { result += n }

		return result
	}
	test_premapped :: proc(path: cstring, file_size: int) -> u64 {
		fd, err := linux.open(path, {})
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer linux.close(fd)

		raw: rawptr = ---
		raw, err = linux.mmap(0, uint(file_size), {.READ}, {.PRIVATE, .POPULATE}, fd)
		if err != nil { log.fatal("Failed to map file:", err) }
		defer linux.munmap(raw, uint(file_size))

		length  := file_size / 8
		numbers := transmute([]u64)runtime.Raw_Slice{raw, length}

		result: u64 = 0
		for n in numbers { result += n }

		return result
	}
	test_threaded :: proc(path: cstring, file_size, buffer_size: int) -> u64 {
		Task :: struct {
			fd:     linux.Fd,
			offset: int,
			size:   int,
			buffer: []byte,
			result: u64,
		}
		worker :: proc(data: rawptr) {
			task := cast(^Task)data

			for task.size > 0 {
				read_size := min(len(task.buffer), task.size)
				for read := 0; read < read_size; {
					n, err := linux.pread(task.fd, task.buffer[read:], i64(task.offset))
					if err != nil { log.fatal("Failed to read file:", err) }

					task.offset += n
					read        += n
				}

				numbers := slice.reinterpret([]u64, task.buffer[:read_size])
				for n in numbers { task.result += n }

				task.size -= read_size
			}
		}

		fd, err := linux.open(path, {})
		if err != nil { log.fatalf("Failed to open %s: %s", path, err) }
		defer linux.close(fd)

		buffer := allocate(4 * buffer_size, populate=true)
		defer free(buffer)

		number_count     := file_size / 8
		number_per_chunk := number_count / 4
		chunk_size       := number_per_chunk * 8

		tasks := [4]Task{
			{fd, 0*chunk_size, chunk_size, buffer[0*buffer_size : 1*buffer_size], 0},
			{fd, 1*chunk_size, chunk_size, buffer[1*buffer_size : 2*buffer_size], 0},
			{fd, 2*chunk_size, chunk_size, buffer[2*buffer_size : 3*buffer_size], 0},
			{fd, 3*chunk_size, file_size - 3*chunk_size, buffer[3*buffer_size : 4*buffer_size], 0},
		}

		thread_0 := thread.create_and_start_with_data(&tasks[0], worker)
		thread_1 := thread.create_and_start_with_data(&tasks[1], worker)
		thread_2 := thread.create_and_start_with_data(&tasks[2], worker)
		thread_3 := thread.create_and_start_with_data(&tasks[3], worker)

		thread.join_multiple(thread_0, thread_1, thread_2, thread_3)

		return tasks[0].result + tasks[1].result + tasks[2].result + tasks[3].result
	}
	test_async :: proc(path: cstring, file_size, buffer_size: int) -> u64 {
		fd, err := linux.open(path, {})
		if err != nil { log.fatalf("Failed to open %s: %s", err) }
		defer linux.close(fd)

		params := uring.DEFAULT_PARAMS

		// NOTE: 8 is used instead of 4, because the core uring wrapper for read
		// calls get_sqe, which by default only works if there are at least 2
		// available entries, which I can't change without reimplementing read.
		ring: uring.Ring = ---
		uring.init(&ring, &params, 8)
		defer uring.destroy(&ring)

		buffer := allocate(4 * buffer_size, populate=true)
		defer free(buffer)

		buffers := [4][]byte{
			buffer[0*buffer_size : 1*buffer_size],
			buffer[1*buffer_size : 2*buffer_size],
			buffer[2*buffer_size : 3*buffer_size],
			buffer[3*buffer_size : 4*buffer_size],
		}

		uring.read(&ring, 0, fd, buffers[0], 0*u64(buffer_size))
		uring.read(&ring, 1, fd, buffers[1], 1*u64(buffer_size))
		uring.read(&ring, 2, fd, buffers[2], 2*u64(buffer_size))
		uring.read(&ring, 3, fd, buffers[3], 3*u64(buffer_size))

		uring.submit(&ring, 0)

		offset    := 4 * buffer_size
		processed := 0
		result    := u64(0)
		for {
			cqe: linux.IO_Uring_CQE = ---
			uring.copy_cqes(&ring, transmute([]linux.IO_Uring_CQE)runtime.Raw_Slice{&cqe, 1}, 1)

			buffer_idx := cqe.user_data
			buffer     := buffers[buffer_idx]
			read       := int(cqe.res)
			numbers    := slice.reinterpret([]u64, buffer[:read])

			if offset < file_size {
				uring.read(&ring, buffer_idx, fd, buffer, u64(offset))
				uring.submit(&ring, 0)

				offset += buffer_size
			}

			for n in numbers { result += n }

			processed += read
			if processed >= file_size { break }
		}

		return result
	}

	path_c := strings.clone_to_cstring(path, context.temp_allocator)

	stat: linux.Statx = ---
	err := linux.statx(linux.AT_FDCWD, path_c, {}, {.SIZE}, &stat)
	if err != nil { log.fatalf("Failed to stat %s: %s", path, err) }
	file_size := int(stat.size)

	reference := test_mapped(path_c, file_size)

	fmt.println("Buffer size (KiB),Serial (GiB/s),Mapped (GiB/s),Premapped (GiB/s),Threaded (GiB/s),Async (GiB/s)")
	for buffer_size := 256*runtime.Kilobyte; buffer_size <= runtime.Gigabyte; buffer_size *= 2 {
		tester: rt.Tester = ---
		result: u64       = ---

		fmt.eprintln(buffer_size / runtime.Kilobyte, "KiB")

		tester = rt.new("serial", file_size)
		for {
			{ rt.scope(&tester)
				result = test_serial(path_c, file_size, buffer_size)
			}
			assert(result == reference)

			if rt.is_done(&tester) { break }
		}
		serial := tester.throughput

		tester = rt.new("mapped", file_size)
		for {
			{ rt.scope(&tester)
				result = test_mapped(path_c, file_size)
			}
			assert(result == reference)

			if rt.is_done(&tester) { break }
		}
		mapped := tester.throughput

		tester = rt.new("premapped", file_size)
		for {
			{ rt.scope(&tester)
				result = test_premapped(path_c, file_size)
			}
			assert(result == reference)

			if rt.is_done(&tester) { break }
		}
		premapped := tester.throughput

		tester = rt.new("threaded", file_size)
		for {
			{ rt.scope(&tester)
				result = test_threaded(path_c, file_size, buffer_size)
			}
			assert(result == reference)

			if rt.is_done(&tester) { break }
		}
		threaded := tester.throughput

		tester = rt.new("async", file_size)
		for {
			{ rt.scope(&tester)
				result = test_async(path_c, file_size, buffer_size)
			}
			assert(result == reference)

			if rt.is_done(&tester) { break }
		}
		async := tester.throughput

		fmt.println(buffer_size, serial, mapped, premapped, threaded, async, sep=",")
	}
}
