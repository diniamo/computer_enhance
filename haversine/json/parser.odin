package json

import "base:runtime"
import "core:os"
import "../prof"

Value :: union {
	string,
	f64,
	bool,
	[]Value,
	map[string]Value,
}

skip_whitespace :: proc(data: uintptr) -> uintptr {
	data := data
	for {
		switch (cast(^u8)data)^ {
		case ' ', '\t', '\n', '\r':
			data += 1
		case:
			return data
		}
	}
}

find_next :: proc(data: uintptr, what: u8) -> uintptr {
	next := data
	for ; (cast(^u8)next)^ != what; next += 1 {}
	return next
}

interval_to_string :: proc(start, after: uintptr) -> string {
	return transmute(string)runtime.Raw_Slice{rawptr(start), int(after - start)}
}

// TODO: handle escape sequences
parse_string :: proc(data: uintptr, allocator: runtime.Allocator) -> (string, uintptr) {
	start    := data + 1
	after    := find_next(start, '"')
	contents := interval_to_string(start, after)
	return contents, after + 1
}

// TODO: scientific notation
parse_positive_number :: proc(data: uintptr) -> (f64, uintptr) {
	data := data
	whole: u64 = 0
	whole_loop: for {
		switch c := (cast(^byte)data)^; c {
		case '0'..='9':
			whole = whole*10 + u64(c - '0')
		case '.':
			data += 1
			break whole_loop
		case:
			return f64(whole), data
		}

		data += 1
	}

	fraction: u64 = 0
	scale:    u64 = 1
	for {
		switch c := (cast(^byte)data)^; c {
		case '0'..='9':
			fraction = fraction*10 + u64(c - '0')
			scale *= 10
		case:
			return f64(whole) + f64(fraction)/f64(scale), data
		}

		data += 1
	}
}

parse_value :: proc(data: uintptr, allocator: runtime.Allocator) -> (Value, uintptr) {
	data := skip_whitespace(data)
	switch (cast(^u8)data)^ {
	case '"':
		return parse_string(data + 1, allocator)
	case '-':
		result, after := parse_positive_number(data + 1)
		return -result, after
	case '0'..='9':
		return parse_positive_number(data)
	case '[':
		list := make([dynamic]Value, allocator)
		for {
			value, after := parse_value(data + 1, allocator)
			append(&list, value)

			data = skip_whitespace(after)
			if (cast(^u8)data)^ == ']' {
				// LEAK
				return list[:], data + 1
			}
		}
	case '{':
		object := make(map[string]Value, allocator)
		for {
			// Key
			data = skip_whitespace(data + 1)
			key, after_key := parse_string(data, allocator)

			// Colon
			data = skip_whitespace(after_key)

			// Value
			value, after_value := parse_value(data + 1, allocator)
			object[key] = value

			data = skip_whitespace(after_value)
			if (cast(^u8)data)^ == '}' {
				// LEAK
				return object, data + 1
			}
		}
	case 'f':
		return false, data + len("false")
	case 't':
		return true, data + len("true")
	case 'n':
		return nil, data + len("null")
	case:
		unreachable()
	}
}

parse_data :: proc(data: []byte, allocator: runtime.Allocator) -> Value { prof.procedure()
	result, _ := parse_value(uintptr(&data[0]), allocator)
	return result
}

parse_path :: proc(path: string, allocator: runtime.Allocator) -> (Value, os.Error) {
	// LEAK
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil { return nil, err }

	return parse_data(data, allocator), nil
}
