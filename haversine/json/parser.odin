package json

import "base:runtime"

Parser :: uintptr

parser :: proc(data: []byte) -> Parser {
	return uintptr(raw_data(data))
}

object :: proc(p: ^Parser) -> bool {
	data := skip_whitespace(p^)
	if (cast(^byte)data)^ == '{' {
		p^ = data + 1
		return true
	} else {
		p^ = data
		return false
	}
}

next_pair :: proc(p: ^Parser) -> (string, bool) {
	data := skip_whitespace(p^)
	char := (cast(^byte)data)^
	if char == ',' {
		data = skip_whitespace(data + 1)
		char = (cast(^byte)data)^
	}

	if char != '}' {
		name, after := parse_string(data)

		data = skip_whitespace(after)
		p^ = data + 1

		return name, true
	} else {
		p^ = data + 1
		return "", false
	}
}

list :: proc(p: ^Parser) -> bool {
	data := skip_whitespace(p^)
	if (cast(^byte)data)^ == '[' {
		p^ = data + 1
		return true
	} else {
		p^ = data
		return false
	}
}

next_element :: proc(p: ^Parser) -> bool {
	data := skip_whitespace(p^)
	char := (cast(^byte)data)^
	if char == ',' {
		data = skip_whitespace(data + 1)
		char = (cast(^byte)data)^
	}

	if char != ']' {
		p^ = data
		return true
	} else {
		p^ = data + 1
		return false
	}
}

str :: proc(p: ^Parser) -> (string, bool) {
	data := skip_whitespace(p^)
	if (cast(^byte)data)^ == '"' {
		result, after := parse_string(data)
		p^ = after
		return result, true
	} else {
		p^ = data
		return "", false
	}
}

number :: proc(p: ^Parser) -> (f64, bool) {
	data := skip_whitespace(p^)
	switch (cast(^byte)data)^ {
	case '-':
		number, after := parse_positive_number(data + 1)
		p^ = after
		return -number, true
	case '0'..='9':
		number, after := parse_positive_number(data)
		p^ = after
		return number, true
	case:
		p^ = data
		return 0, false
	}
}

boolean :: proc(p: ^Parser) -> (bool, bool) {
	data := skip_whitespace(p^)
	switch (cast(^byte)data)^ {
	case 't':
		p^ = data + len("true")
		return true, true
	case 'f':
		p^ = data + len("false")
		return false, true
	case:
		p^ = data
		return false, false
	}
}

null :: proc(p: ^Parser) -> bool {
	data := skip_whitespace(p^)
	if (cast(^byte)data)^ == 'n' {
		p^ = data + len("null")
		return true
	} else {
		p^ = data
		return false
	}
}

skip_whitespace :: proc(data: uintptr) -> uintptr {
	data := data
	for {
		switch (cast(^byte)data)^ {
		case ' ', '\t', '\n', '\r':
			data += 1
		case:
			return data
		}
	}
}

// TODO: handle escape sequences
parse_string :: proc(data: uintptr) -> (string, uintptr) {
	start := data + 1
	after := start
	for ; (cast(^byte)after)^ != '"'; after += 1 {}

	contents := transmute(string)runtime.Raw_Slice{rawptr(start), int(after - start)}
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
