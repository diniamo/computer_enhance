package ga

import "base:runtime"
import "base:intrinsics"
import "core:mem"
import vmem "core:mem/virtual"

DEFAULT_RESERVATION :: 64 * mem.Gigabyte

Arena :: struct {
	memory, position: uintptr,
	reserved, committed, page_size: uint
}

create :: proc "contextless" () -> Arena {
	memory, _ := vmem.reserve(DEFAULT_RESERVATION)
	pointer   := uintptr(raw_data(memory))

	return {
		memory    = pointer,
		position  = pointer,
		reserved  = DEFAULT_RESERVATION,
		page_size = uint(mem.PAGE_SIZE)
	}
}

delete :: proc "contextless" (arena: ^Arena) {
	vmem.release(rawptr(arena.memory), arena.reserved)
}

ensure_space :: proc "contextless" (arena: ^Arena, size: int) {
	past_required := arena.position + uintptr(size)
	past_arena    := arena.memory + uintptr(arena.committed)

	if past_required > past_arena {
		required   := uint(past_required - past_arena)
		page_count := required/arena.page_size + 1
		growth     := page_count * arena.page_size

		vmem.commit(rawptr(past_arena), growth)
		arena.committed += growth
	}
}

allocate :: proc "contextless" (arena: ^Arena, size: int, alignment := mem.DEFAULT_ALIGNMENT) -> []byte {
	align_forward :: #force_inline proc "contextless" (pointer, alignment: uintptr) -> uintptr {
		return (pointer + alignment-1) & ~(alignment-1)
	}
	start := align_forward(arena.position, uintptr(alignment))

	arena.position = start
	ensure_space(arena, size)

	arena.position += uintptr(size)
	return transmute([]byte)runtime.Raw_Slice{rawptr(start), size}
}

resize :: proc "contextless" (arena: ^Arena, old: []byte, size, alignment: int) -> []byte {
	old_pointer := uintptr(raw_data(old))
	past_old    := old_pointer + uintptr(len(old))

	if past_old == arena.position {
		delta := size - len(old)
		ensure_space(arena, delta)
		arena.position += uintptr(delta)
		return transmute([]byte)runtime.Raw_Slice{rawptr(old_pointer), size}
	} else {
		new := allocate(arena, size, alignment)
		copy(new, old)
		return new
	}
}

free_all :: proc "contextless" (arena: ^Arena) {
	intrinsics.mem_zero(rawptr(arena.memory), arena.position - arena.memory)
	arena.position = arena.memory
}

allocator_proc :: proc (data: rawptr, mode: runtime.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, _ := #caller_location) -> ([]byte, runtime.Allocator_Error) {
	arena := cast(^Arena)data

	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		return allocate(arena, size, alignment), nil
	case .Free_All:
		free_all(arena)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		old_slice := transmute([]byte)runtime.Raw_Slice{old_memory, old_size}
		return resize(arena, old_slice, size, alignment), nil
	case .Query_Features:
		set := cast(^runtime.Allocator_Mode_Set)old_memory
		set^ = {.Alloc, .Alloc_Non_Zeroed, .Free_All, .Resize, .Resize_Non_Zeroed, .Query_Features, .Query_Info}
		return transmute([]byte)runtime.Raw_Slice{old_memory, size_of(runtime.Allocator_Mode_Set)}, nil
	case .Query_Info:
		info := cast(^runtime.Allocator_Query_Info)old_memory
		info^ = {
			pointer   = data,
			size      = int(arena.reserved),
			alignment = int(arena.page_size)
		}
		return transmute([]byte)runtime.Raw_Slice{old_memory, size_of(runtime.Allocator_Query_Info)}, nil
	}

	return nil, nil
}

allocator :: proc "contextless" (arena: ^Arena) -> runtime.Allocator {
	return {
		procedure = allocator_proc,
		data      = arena
	}
}
