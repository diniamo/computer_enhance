package cpu_8086

import "core:io"

// I rely on pointer arithmetic to resolve low/high bytes
// The endianness is static in a real CPU anyway
#assert(ODIN_ENDIAN == .Little)

import "core:os"
import "core:fmt"

Operand :: struct {
	name: string,
	data: rawptr,
	word: bool,
}

Flag :: enum {
	Sign,
	Zero,
}
Flags :: bit_set[Flag; u16]

MEMORY_SIZE :: 1024 * 1024

REGISTER_SIZE  :: 3
REGISTER_COUNT :: 1 << REGISTER_SIZE

// <1 bit word><3 bit reg>
OPERAND_SIZE  :: REGISTER_SIZE + 1
OPERAND_COUNT :: 1 << OPERAND_SIZE

REG_AX :: 0
REG_CX :: 1
REG_DX :: 2
REG_BX :: 3
REG_SP :: 4
REG_BP :: 5
REG_SI :: 6
REG_DI :: 7

OP_AL :: 0
OP_CL :: 1
OP_DL :: 2
OP_BL :: 3
OP_AH :: 4
OP_CH :: 5
OP_DH :: 6
OP_BH :: 7
OP_AX :: 8
OP_CX :: 9
OP_DX :: 10
OP_BX :: 11
OP_SP :: 12
OP_BP :: 13
OP_SI :: 14
OP_DI :: 15

memory:    [MEMORY_SIZE]byte
registers: [REGISTER_COUNT]u16
ip:        u16
flags:     Flags

total_cycles: uint

register_operands := [OPERAND_COUNT]Operand{
	{"al", &registers[REG_AX], false},
	{"cl", &registers[REG_CX], false},
	{"dl", &registers[REG_DX], false},
	{"bl", &registers[REG_BX], false},
	{"ah", rawptr(uintptr(&registers[REG_AX]) + 1), false},
	{"ch", rawptr(uintptr(&registers[REG_CX]) + 1), false},
	{"dh", rawptr(uintptr(&registers[REG_DX]) + 1), false},
	{"bh", rawptr(uintptr(&registers[REG_BX]) + 1), false},

	{"ax", &registers[REG_AX], true},
	{"cx", &registers[REG_CX], true},
	{"dx", &registers[REG_DX], true},
	{"bx", &registers[REG_BX], true},
	{"sp", &registers[REG_SP], true},
	{"bp", &registers[REG_BP], true},
	{"si", &registers[REG_SI], true},
	{"di", &registers[REG_DI], true},
}

main :: proc() {
	path      := os.args[1]
	file, err := os.open(path)
	if err != nil { fatalf("Failed to open %s: %s", path, err) }

	program_size := 0
	for {
		n, err := os.read(file, memory[program_size:])
		if err != nil {
			if err, ok := err.(io.Error); ok && err == .EOF {
				break
			} else {
				fatal("Failed to read file:", err)
			}
		}

		program_size += n
	}

	os.close(file)

	fmt.println(";", path, "disassembly")
	fmt.println("bits 16")
	fmt.println()

	for ip < u16(program_size) {
		old_registers := registers
		old_ip        := ip
		old_flags     := flags

		instruction := memory[ip]
		cycles: uint

		switch instruction {
		// mov: register <-> register/memory
		case 0b10001000, 0b10001001, 0b10001010, 0b10001011:
			dst, src, bytes, ea_cycles := resolve_reg_rm(memory[ip:])
			ip += bytes
			mov(dst, src)
			cycles = is_memory(dst) ? 9 + ea_cycles : (is_memory(src) ? 8 + ea_cycles : 2)
		// mov: immediate -> register/memory
		case 0b11000110, 0b11000111:
			dst, src, bytes, ea_cycles := resolve_im_rm(memory[ip:], false)
			ip += bytes
			mov(dst, src)
			cycles = is_memory(dst) ? 10 + ea_cycles : 4
		// mov: immediate -> register
		case 0b10110000, 0b10110001, 0b10110010, 0b10110011, 0b10110100, 0b10110101, 0b10110110, 0b10110111, 0b10111000, 0b10111001, 0b10111010, 0b10111011, 0b10111100, 0b10111101, 0b10111110, 0b10111111:
			dst := register_operands[instruction & 0b1111]

			value: u16 = ---
			word: bool = ---
			if dst.word {
				value = (u16(memory[ip + 2]) << 8) | u16(memory[ip + 1])
				word  = true

				ip += 3
			} else {
				value = u16(memory[ip + 1])
				word  = false

				ip += 2
			}
			src := Operand{
				name = fmt.tprint(value),
				data = &value,
				word = word,
			}

			mov(dst, src)

			cycles = 4

		// add: register <-> register/memory
		case 0b00000000, 0b00000001, 0b00000010, 0b00000011:
			dst, src, bytes, ea_cycles := resolve_reg_rm(memory[ip:])
			ip += bytes
			add(dst, src)
			cycles = is_memory(dst) ? 16 + ea_cycles : (is_memory(src) ? 9 + ea_cycles : 3)
		// add: immediate -> accumulator
		case 0b00000100, 0b00000101:
			dst, src, bytes := resolve_ax_im(memory[ip:])
			ip += bytes
			add(dst, src)
			cycles = 4

		// sub: register <-> register/memory
		case 0b00101000, 0b00101001, 0b00101010, 0b00101011:
			dst, src, bytes, ea_cycles := resolve_reg_rm(memory[ip:])
			ip += bytes
			sub(dst, src)
			cycles = is_memory(dst) ? 16 + ea_cycles : (is_memory(src) ? 9 + ea_cycles : 3)
		// sub: immediate -> accumulator
		case 0b00101100, 0b00101101:
			dst, src, bytes := resolve_ax_im(memory[ip:])
			ip += bytes
			sub(dst, src)
			cycles = 4

		// cmp: register <-> register/memory
		case 0b00111000, 0b00111001, 0b00111010, 0b00111011:
			dst, src, bytes, ea_cycles := resolve_reg_rm(memory[ip:])
			ip += bytes
			cmp(dst, src)
			cycles = is_register(dst) && is_register(src) ? 3 : 9 + ea_cycles
		// cmp: immediate -> accumulator
		case 0b00111100, 0b00111101:
			dst, src, bytes := resolve_ax_im(memory[ip:])
			ip += bytes
			cmp(dst, src)
			cycles = 4

		// add, sub, cmp: immediate -> register/memory
		case 0b10000000, 0b10000001, 0b10000010, 0b10000011:
			dst, src, bytes, ea_cycles := resolve_im_rm(memory[ip:], true)
			ip += bytes
			switch instruction := (memory[ip + 1] >> 3) & 0b111; instruction {
			case 0b000: add(dst, src); cycles = is_memory(dst) ? 17 + ea_cycles : 4
			case 0b101: sub(dst, src); cycles = is_memory(dst) ? 17 + ea_cycles : 4
			case 0b111: cmp(dst, src); cycles = is_memory(dst) ? 10 + ea_cycles : 4
			}

		// je/jz
		case 0b01110100:
			resolve_jump("je", memory[ip:])
			ip += 2
		// jl/jnge
		case 0b01111100:
			resolve_jump("jl", memory[ip:])
			ip += 2
		// jle/jng
		case 0b01111110:
			resolve_jump("jle", memory[ip:])
			ip += 2
		// jb/jnae
		case 0b01110010:
			resolve_jump("jb", memory[ip:])
			ip += 2
		// jbe/jna
		case 0b01110110:
			resolve_jump("jbe", memory[ip:])
			ip += 2
		// jp/jpe
		case 0b01111010:
			resolve_jump("jp", memory[ip:])
			ip += 2
		// jo
		case 0b01110000:
			resolve_jump("jo", memory[ip:])
			ip += 2
		// js
		case 0b01111000:
			resolve_jump("js", memory[ip:])
			ip += 2
		// jne/jnz
		case 0b01110101:
			inc := resolve_jump("jnz", memory[ip:])
			ip += 2
			if .Zero not_in flags {
				ip = u16(i32(ip) + i32(inc))
			}
		// jnl/jge
		case 0b01111101:
			resolve_jump("jnl", memory[ip:])
			ip += 2
		// jnle/jg
		case 0b01111111:
			resolve_jump("jg", memory[ip:])
			ip += 2
		// jnb/jae
		case 0b01110011:
			resolve_jump("jnb", memory[ip:])
			ip += 2
		// jnbe/ja
		case 0b01110111:
			resolve_jump("ja", memory[ip:])
			ip += 2
		// jnp/jpo
		case 0b01111011:
			resolve_jump("jnp", memory[ip:])
			ip += 2
		// jno
		case 0b01110001:
			resolve_jump("jno", memory[ip:])
			ip += 2
		// jns
		case 0b01111001:
			resolve_jump("jns", memory[ip:])
			ip += 2
		// loop
		case 0b11100010:
			resolve_jump("loop", memory[ip:])
			ip += 2
		// loopz/loope
		case 0b11100001:
			resolve_jump("loopz", memory[ip:])
			ip += 2
		// loopnz/loopne
		case 0b11100000:
			resolve_jump("loopnz", memory[ip:])
			ip += 2
		// jcxz
		case 0b11100011:
			resolve_jump("jcxz", memory[ip:])
			ip += 2

		case:
			fmt.print("nop")
			ip += 1
		}
		total_cycles += cycles

		fmt.printf(" ; cycles: +%d = %d", cycles, total_cycles)
		for i: u8 = 0; i < REGISTER_COUNT; i += 1 {
			if registers[i] != old_registers[i] {
				fmt.printf(", %s: %d -> %d", register_operands[0b1000 | i].name, old_registers[i], registers[i])
			}
		}
		if old_ip != ip {
			fmt.printf(", ip: %d -> %d", old_ip, ip)
		}
		if flags != old_flags {
			fmt.printf(", flags: %v -> %v", old_flags, flags)
		}

		fmt.println()

		free_all(context.temp_allocator)
	}

	fmt.println()

	fmt.println("; cycles:", total_cycles)
	for i: u8 = 0; i < REGISTER_COUNT; i += 1 {
		if registers[i] != 0 {
			fmt.printfln("; %s: %d", register_operands[0b1000 | i].name, registers[i])
		}
	}
	fmt.println("; ip:", ip)
	fmt.println("; flags:", flags)

	err = os.write_entire_file("memory.data", memory[:])
	if err != nil { fmt.eprintln("Failed to dump memory:", err) }
}

resolve_rm :: proc(stream: []byte) -> (Operand, u16, uint) {
	instruction := stream[0]
	word        := instruction & 1

	data := stream[1]
	mode := (data >> 6) & 0b11
	reg  := (data >> 3) & 0b111
	rm   := data & 0b111

	op:     Operand = ---
	bytes:  u16     = ---
	cycles: uint    = ---

	switch mode {
	// No displacement or 16-bit direct address
	case 0b00:
		if rm != 0b110 {
			op, cycles = resolve_ea(rm, 0)
			bytes      = 0
		} else {
			low  := stream[2]
			high := stream[3]
			disp := u16(high) << 8 | u16(low)

			op = {
				name = fmt.tprintf("[%d]", disp),
				data = &memory[disp],
				word = true,
			}
			bytes  = 2
			cycles = 6
		}

	// 8-bit displacement
	case 0b01:
		disp := stream[2]

		op, cycles = resolve_ea(rm, u16(disp))
		bytes      = 1

	// 16-bit displacement
	case 0b10:
		low  := stream[2]
		high := stream[3]
		disp := u16(high) << 8 | u16(low)

		op, cycles = resolve_ea(rm, disp)
		bytes      = 2

	// register -> register
	case 0b11:
		op     = register_operands[(word << 3) | rm]
		bytes  = 0
		cycles = 0
	}

	return op, bytes, cycles
}

resolve_reg_rm :: proc(stream: []byte) -> (Operand, Operand, u16, uint) {
	instruction := stream[0]
	reg_is_dst  := (instruction >> 1) & 1 == 1
	word        := instruction & 1

	data := stream[1]
	reg  := (data >> 3) & 0b111

	reg_operand                    := register_operands[(word << 3) | reg]
	rm_operand, disp_bytes, cycles := resolve_rm(stream)

	dst := reg_is_dst ? reg_operand : rm_operand
	src := reg_is_dst ? rm_operand  : reg_operand

	return dst, src, 2 + disp_bytes, cycles
}

resolve_im_rm :: proc(stream: []byte, extensible: bool) -> (Operand, Operand, u16, uint) {
	instruction := stream[0]
	extend      := extensible && (instruction >> 1) & 1 == 1
	word        := (instruction >> 0) & 1 == 1

	data      := stream[1]
	rm_is_reg := (data >> 6) & 0b11 == 0b11

	rm_operand, disp_bytes, cycles := resolve_rm(stream)
	if !rm_is_reg {
		rm_operand.name = fmt.tprintf(word ? "word %s" : "byte %s", rm_operand.name)
	}

	bytes := 2 + disp_bytes

	immediate := u16(stream[bytes])
	bytes += 1

	// The high bit of mode means we should extend the sign (highest bit) of the low byte to all bits of the high byte,
	// the low bit means we are operating on a word. This means 0b10 doesn't make any sense (extend == true => word != true).
	if extend {
		immediate |= u16(0 - (u8(immediate) >> 7)) << 8
	} else if word {
		immediate |= u16(stream[bytes]) << 8
		bytes += 1
	}

	immediate_data := new(u16, context.temp_allocator)
	immediate_data^ = immediate
	immediate_operand := Operand{
		name = fmt.tprint(immediate),
		data = immediate_data,
		word = word,
	}

	return rm_operand, immediate_operand, bytes, cycles
}

resolve_ax_im :: proc(stream: []byte) -> (Operand, Operand, u16) {
	instruction := stream[0]
	word        := instruction & 1 == 1

	if word {
		value := u16(stream[2]) << 8 | u16(stream[1])

		data := new(u16, context.temp_allocator)
		data^ = value

		return register_operands[OP_AX], {fmt.tprint(value), data, true}, 3
	} else {
		value := stream[1]

		data := new(u8, context.temp_allocator)
		data^ = value

		return register_operands[OP_AL], {fmt.tprint(value), data, false}, 2
	}
}

resolve_jump :: proc(instruction: string, stream: []byte) -> i8 {
	inc := i8(stream[1])

	// The increment is relative to after the decoded jump instruction,
	// becuase the instruction pointer is incremented before execution,
	// but $ means the start of the current instruction in assembly,
	// so 2 is added to correct for that (every jump instruction is 2 bytes).
	fmt.printf("%s $%+i", instruction, inc + 2)

	return inc
}

resolve_ea :: proc(rm: byte, disp: u16) -> (Operand, uint) {
	ea:     string = ---
	data:   rawptr = ---
	cycles: uint   = ---

	switch rm {
	case 0b000:
		ea     = "bx + si"
		data   = &memory[registers[REG_BX] + registers[REG_SI] + disp]
		cycles = 7
	case 0b001:
		ea     = "bx + di"
		data   = &memory[registers[REG_BX] + registers[REG_DI] + disp]
		cycles = 8
	case 0b010:
		ea     = "bp + si"
		data   = &memory[registers[REG_BP] + registers[REG_SI] + disp]
		cycles = 8
	case 0b011:
		ea     = "bp + di"
		data   = &memory[registers[REG_BP] + registers[REG_DI] + disp]
		cycles = 7
	case 0b100:
		ea     = "si"
		data   = &memory[registers[REG_SI] + disp]
		cycles = 5
	case 0b101:
		ea     = "di"
		data   = &memory[registers[REG_DI] + disp]
		cycles = 5
	case 0b110:
		ea     = "bp"
		data   = &memory[registers[REG_BP] + disp]
		cycles = 5
	case 0b111:
		ea     = "bx"
		data   = &memory[registers[REG_BX] + disp]
		cycles = 5
	case:
		unreachable()
	}

	if disp != 0 {
		ea = fmt.tprintf("[%s + %d]", ea, disp)
		cycles += 4
	} else {
		ea = fmt.tprintf("[%s]", ea)
	}

	return {ea, data, true}, cycles
}

mov :: proc(dst, src: Operand) {
	fmt.printf("mov %s, %s", dst.name, src.name)

	if dst.word {
		(cast(^u16)dst.data)^ = (cast(^u16)src.data)^
	} else {
		(cast(^u8)dst.data)^ = (cast(^u8)src.data)^
	}
}

add :: proc(dst, src: Operand) {
	fmt.printf("add %s, %s", dst.name, src.name)

	if dst.word {
		dst := cast(^u16)dst.data
		src := cast(^u16)src.data

		value := dst^ + src^
		dst^ = value
	} else {
		dst := cast(^u8)dst.data
		src := cast(^u8)src.data

		value := dst^ + src^
		dst^ = value
	}

	update_flags(dst)
}

sub :: proc(dst, src: Operand) {
	fmt.printf("sub %s, %s", dst.name, src.name)

	if dst.word {
		dst := cast(^u16)dst.data
		src := cast(^u16)src.data

		value := dst^ - src^
		dst^ = value
	} else {
		dst := cast(^u8)dst.data
		src := cast(^u8)src.data

		value := dst^ - src^
		dst^ = value
	}

	update_flags(dst)
}

cmp :: proc(dst, src: Operand) {
	fmt.printf("cmp %s, %s", dst.name, src.name)

	if dst.word {
		value := (cast(^u16)dst.data)^ - (cast(^u16)src.data)^
		update_flags({"", &value, true})
	} else {
		value := (cast(^u8)dst.data)^ - (cast(^u8)src.data)^
		update_flags({"", &value, false})
	}
}

update_flags :: proc(op: Operand) {
	if op.word {
		value := (cast(^i16)op.data)^

		flags = {}
		if value < 0       { flags += {.Sign} }
		else if value == 0 { flags += {.Zero} }
	} else {
		value := (cast(^i8)op.data)^

		flags = {}
		if value < 0       { flags += {.Sign} }
		else if value == 0 { flags += {.Zero} }
	}
}

fatal :: proc(args: ..any) {
	fmt.eprintln(..args)
	os.exit(1)
}
fatalf :: proc(format: string, args: ..any) {
	fmt.eprintfln(format, ..args)
	os.exit(1)
}

is_register :: proc(op: Operand) -> bool {
	data := uintptr(op.data)
	base := uintptr(&registers[0])
	return base <= data && data < base + len(registers)*size_of(u16)
}

is_memory :: proc(op: Operand) -> bool {
	data := uintptr(op.data)
	base := uintptr(&memory[0])
	return base <= data && data < base + len(memory)
}
