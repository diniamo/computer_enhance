package logger

import "core:terminal"
import "core:terminal/ansi"
import "core:strings"
import "core:os"
import "core:log"

default := log.Logger{
	lowest_level = .Debug when ODIN_DEBUG else .Info,
	options      = terminal.color_enabled ? {.Terminal_Color} : {},
	procedure    = proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
		builder := strings.builder_make(context.temp_allocator)

		color := .Terminal_Color in options
		if color {
			color: string = ---
			switch level {
			case .Debug:   color = ansi.FG_DEFAULT
			case .Info:    color = ansi.FAINT
			case .Warning: color = ansi.FG_YELLOW
			case .Error:   color = ansi.FG_RED
			case .Fatal:   color = ansi.FG_RED + ";" + ansi.BOLD
			}

			strings.write_string(&builder, ansi.CSI)
			strings.write_string(&builder, color)
			strings.write_string(&builder, ansi.SGR)
		}

		strings.write_string(&builder, text)
		if color {
			strings.write_string(&builder, ansi.CSI + ansi.RESET + ansi.SGR)
		}
		strings.write_byte(&builder, '\n')

		output := strings.to_string(builder)
		os.write(os.stderr, transmute([]u8)output)

		if level == .Fatal {
			os.exit(1)
		}
	}
}
