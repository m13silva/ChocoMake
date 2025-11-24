package parser

import "../types"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:text/regex"

// ============================================================================
// TOKENIZER
// ============================================================================

TokenKind :: enum {
	EOF,
	Newline,
	Comment,
	Identifier,
	Colon,
	Equal,
	LeftBracket,
	RightBracket,
	LeftSquare,
	RightSquare,
	Comma,
	String,
	Keyword,
	Dot,
	At,
}

Token :: struct {
	kind:       TokenKind,
	value:      string,
	line:       int,
	col:        int,
	byte_start: int, // Posición en la entrada original
	byte_end:   int, // Posición final en la entrada original
}

Tokenizer :: struct {
	input:    string, // Entrada de texto
	position: int, // Posición actual
	line:     int, // Línea actual
	col:      int, // Columna actual
}

make_tokenizer :: proc(input: string) -> Tokenizer {
	return Tokenizer{input = input, position = 0, line = 1, col = 1}
}

peek_char :: proc(t: ^Tokenizer, offset := 0) -> u8 {
	pos := t.position + offset
	if pos >= len(t.input) {
		return 0
	}
	return t.input[pos]
}

advance :: proc(t: ^Tokenizer) -> u8 {
	if t.position >= len(t.input) {
		return 0
	}
	ch := t.input[t.position]
	t.position += 1
	if ch == '\n' {
		t.line += 1
		t.col = 1
	} else {
		t.col += 1
	}
	return ch
}

skip_whitespace :: proc(t: ^Tokenizer) {
	for {
		ch := peek_char(t)
		if ch == ' ' || ch == '\t' || ch == '\r' {
			advance(t)
		} else {
			break
		}
	}
}

read_identifier :: proc(t: ^Tokenizer) -> string {
	start := t.position
	for {
		ch := peek_char(t)
		if (ch >= 'a' && ch <= 'z') ||
		   (ch >= 'A' && ch <= 'Z') ||
		   (ch >= '0' && ch <= '9') ||
		   ch == '_' ||
		   ch == '-' ||
		   ch == '/' ||
		   ch == '@' ||
		   ch == '{' ||
		   ch == '}' {
			advance(t)
		} else {
			break
		}
	}
	return t.input[start:t.position]
}

read_string :: proc(t: ^Tokenizer) -> string {
	quote := advance(t) // consumir comilla de apertura
	start := t.position
	escaped := false

	for {
		ch := peek_char(t)
		if ch == 0 {
			break
		}
		if escaped {
			advance(t)
			escaped = false
			continue
		}
		if ch == '\\' {
			escaped = true
			advance(t)
			continue
		}
		if ch == quote {
			result := t.input[start:t.position]
			advance(t) // consumir comilla de cierre
			return result
		}
		advance(t)
	}
	return t.input[start:t.position]
}

read_line_content :: proc(t: ^Tokenizer) -> string {
	start := t.position
	for {
		ch := peek_char(t)
		if ch == '\n' || ch == 0 {
			break
		}
		advance(t)
	}
	return strings.trim_right_space(t.input[start:t.position])
}

next_token :: proc(t: ^Tokenizer) -> Token {
	skip_whitespace(t)

	line := t.line
	col := t.col
	byte_start := t.position
	ch := peek_char(t)

	if ch == 0 {
		return Token {
			kind = .EOF,
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = byte_start,
		}
	}

	// Nueva línea
	if ch == '\n' {
		advance(t)
		return Token {
			kind = .Newline,
			value = "\n",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	}

	// Comentario
	if ch == '#' {
		advance(t)
		comment := read_line_content(t)
		return Token {
			kind = .Comment,
			value = comment,
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	}

	// Tokens de un solo carácter
	switch ch {
	case ':':
		advance(t)
		return Token {
			kind = .Colon,
			value = ":",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	case '=':
		advance(t)
		return Token {
			kind = .Equal,
			value = "=",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	case '[':
		advance(t)
		return Token {
			kind = .LeftSquare,
			value = "[",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	case ']':
		advance(t)
		return Token {
			kind = .RightSquare,
			value = "]",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	case ',':
		advance(t)
		return Token {
			kind = .Comma,
			value = ",",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	case '.':
		advance(t)
		return Token {
			kind = .Dot,
			value = ".",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	case '@':
		advance(t)
		return Token {
			kind = .At,
			value = "@",
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	}

	// Literales de cadena
	if ch == '"' {
		value := read_string(t)
		return Token {
			kind = .String,
			value = value,
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	}

	// Identificador o palabra clave
	if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' {
		value := read_identifier(t)

		// Verificar palabras clave
		kind := TokenKind.Identifier
		switch value {
		case "selector", "template", "env", "default", "build", "run", "copy", "clean", "flags":
			kind = .Keyword
		}

		return Token {
			kind = kind,
			value = value,
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	}

	// Alternativa: leer como identificador
	value := read_identifier(t)
	if len(value) > 0 {
		return Token {
			kind = .Identifier,
			value = value,
			line = line,
			col = col,
			byte_start = byte_start,
			byte_end = t.position,
		}
	}

	// Carácter desconocido, omitirlo
	advance(t)
	return next_token(t)
}

tokenize :: proc(input: string) -> [dynamic]Token {
	tokens := make([dynamic]Token)
	tokenizer := make_tokenizer(input)

	for {
		token := next_token(&tokenizer)
		append(&tokens, token)
		if token.kind == .EOF {
			break
		}
	}

	return tokens
}

// ============================================================================
// PARSER
// ============================================================================

Parser :: struct {
	tokens:   []Token,
	position: int,
	config:   types.Config,
	input:    string, // Entrada original para extraer texto sin procesar
}

make_parser :: proc(tokens: []Token, input: string) -> Parser {
	parser := Parser {
		tokens   = tokens,
		position = 0,
		input    = input,
	}
	parser.config.targets = make(map[string]types.Target)
	parser.config.variables = make(map[string]types.Variable)
	return parser
}

current_token :: proc(p: ^Parser) -> Token {
	if p.position >= len(p.tokens) {
		return p.tokens[len(p.tokens) - 1] // Retornar EOF
	}
	return p.tokens[p.position]
}

peek_token :: proc(p: ^Parser, offset := 1) -> Token {
	pos := p.position + offset
	if pos >= len(p.tokens) {
		return p.tokens[len(p.tokens) - 1] // Retornar EOF
	}
	return p.tokens[pos]
}

advance_parser :: proc(p: ^Parser) {
	if p.position < len(p.tokens) - 1 {
		p.position += 1
	}
}

skip_newlines :: proc(p: ^Parser) {
	for current_token(p).kind == .Newline {
		advance_parser(p)
	}
}

expect :: proc(p: ^Parser, kind: TokenKind) -> bool {
	if current_token(p).kind == kind {
		advance_parser(p)
		return true
	}
	return false
}

// Leer todos los tokens hasta nueva línea o EOF - extrae de la entrada original
read_until_newline :: proc(p: ^Parser) -> string {
	// Encontrar la posición inicial del token actual
	start_tok := current_token(p)
	if start_tok.kind == .Newline || start_tok.kind == .EOF {
		return ""
	}

	start_pos := start_tok.byte_start
	end_pos := start_pos

	// Avanzar hasta encontrar nueva línea o EOF, rastreando la posición final
	for {
		tok := current_token(p)
		if tok.kind == .Newline || tok.kind == .EOF {
			break
		}
		if tok.kind != .Comment {
			end_pos = tok.byte_end
		}
		advance_parser(p)
	}

	// Extraer el texto original de la entrada
	if end_pos > start_pos && end_pos <= len(p.input) {
		return strings.clone(strings.trim_space(p.input[start_pos:end_pos]))
	}

	return ""
}

// Analizar un valor después de '=' o ':'
parse_value :: proc(p: ^Parser) -> string {
	skip_whitespace_tokens(p)

	tok := current_token(p)
	if tok.kind == .String {
		value := tok.value
		advance_parser(p)
		return value
	}

	// Leer todo hasta nueva línea
	return read_until_newline(p)
}

skip_whitespace_tokens :: proc(p: ^Parser) {
	// Los tokens ya omiten espacios en blanco, pero omitimos comentarios
	for current_token(p).kind == .Comment {
		advance_parser(p)
	}
}

// Analizar flags: [debug, release]
parse_flags :: proc(p: ^Parser) {
	// flags : [debug,release]
	// El token actual debería ser 'flags'
	advance_parser(p) // omitir 'flags'
	skip_whitespace_tokens(p)

	if !expect(p, .Colon) {
		return
	}

	skip_whitespace_tokens(p)

	// Esperar '['
	if !expect(p, .LeftSquare) {
		return
	}

	flags := make([dynamic]string)

	for {
		skip_whitespace_tokens(p)
		tok := current_token(p)

		if tok.kind == .RightSquare {
			advance_parser(p)
			break
		}

		if tok.kind == .Identifier || tok.kind == .Keyword {
			append(&flags, tok.value)
			advance_parser(p)
		} else if tok.kind == .Comma {
			advance_parser(p)
		} else {
			break
		}
	}

	p.config.flags = flags[:]
}

// Analizar variable de entorno: env.OS
parse_env_variable :: proc(p: ^Parser) {
	// env.OS
	advance_parser(p) // omitir 'env'
	if !expect(p, .Dot) {
		return
	}

	tok := current_token(p)
	if tok.kind != .Identifier {
		return
	}

	name := tok.value
	advance_parser(p)

	// Verificar si la variable ya existe
	if name in p.config.variables {
		return
	}

	env_value := os.get_env(name)

	if env_value != "" {
		p.config.variables[name] = types.Variable {
			name  = name,
			kind  = .Normal,
			value = env_value,
		}
	}
}

// Verificar si el valor contiene referencias de plantilla como {var}
undefinedType2 :: proc(value: string) -> bool {
	pattern, _ := regex.create_iterator(value, `\{([^}]+)\}`)
	_, _, ok := regex.match(&pattern)
	return ok
}

// Analizar variable normal: name = "value"
parse_variable :: proc(p: ^Parser) {
	name := current_token(p).value
	advance_parser(p) // omitir nombre

	skip_whitespace_tokens(p)

	if !expect(p, .Equal) {
		return
	}

	// Chequear si la variable ya existe
	if name in p.config.variables {
		fmt.println("variable ya existe:", name)
		// Omitir el resto de la línea
		for current_token(p).kind != .Newline && current_token(p).kind != .EOF {
			advance_parser(p)
		}
		return
	}

	skip_whitespace_tokens(p)

	value := parse_value(p)

	// Eliminar comillas si están presentes
	value = strings.trim(value, "\"")

	// Verificar si es una referencia
	if undefinedType2(value) {
		p.config.variables[name] = types.Variable {
			name  = name,
			kind  = .Reference,
			value = value,
		}
	} else {
		p.config.variables[name] = types.Variable {
			name  = name,
			kind  = .Normal,
			value = value,
		}
	}
}

// Analizar selector: win_flag: selector flags
parse_selector :: proc(p: ^Parser) {
	name := current_token(p).value
	advance_parser(p) // omitir nombre

	if !expect(p, .Colon) {
		return
	}

	skip_whitespace_tokens(p)

	// Esperar palabra clave 'selector'
	if current_token(p).value != "selector" {
		return
	}
	advance_parser(p)

	skip_whitespace_tokens(p)

	// Leer fuente (ej., "flags" o "group")
	source := "flags"
	if current_token(p).kind == .Identifier || current_token(p).kind == .Keyword {
		source = current_token(p).value
		advance_parser(p)
	}

	// Saltar a la siguiente línea
	for current_token(p).kind != .Newline && current_token(p).kind != .EOF {
		advance_parser(p)
	}
	skip_newlines(p)

	// Leer entradas de mapeo
	mapping := make(map[string]string)

	for {
		skip_newlines(p)
		tok := current_token(p)

		// Detener si encontramos una nueva sección o EOF
		if tok.kind == .LeftSquare || tok.kind == .EOF {
			break
		}

		// Verificar si esta es una línea de mapeo (clave: valor)
		if tok.kind == .Identifier {
			next := peek_token(p)
			if next.kind == .Colon {
				// Verificar si esta es una declaración de selector o plantilla
				next2 := peek_token(p, 2)
				if next2.kind == .Keyword &&
				   (next2.value == "selector" || next2.value == "template") {
					// Este es un nuevo selector/plantilla, detener aquí
					break
				}

				key := tok.value
				advance_parser(p) // omitir clave
				advance_parser(p) // omitir dos puntos

				skip_whitespace_tokens(p)
				value := parse_value(p)
				mapping[key] = value

				skip_newlines(p)
			} else {
				break
			}
		} else {
			break
		}
	}

	// Verificar si la variable ya existe
	if name in p.config.variables {
		fmt.println("variable ya existe:", name)
		return
	}

	p.config.variables[name] = types.Variable {
		name = name,
		kind = .Selector,
		value = types.Selector{source = source, mapping = mapping},
	}
}

// Analizar plantilla: collections: template -collection:key:a1
parse_template :: proc(p: ^Parser) {
	name := current_token(p).value
	advance_parser(p) // omitir nombre

	if !expect(p, .Colon) {
		return
	}

	skip_whitespace_tokens(p)

	// Esperar palabra clave 'template'
	if current_token(p).value != "template" {
		return
	}
	advance_parser(p)

	skip_whitespace_tokens(p)

	// Leer patrón
	pattern := parse_value(p)

	skip_newlines(p)

	// Leer entradas de plantilla
	entries := make([dynamic]types.TemplateEntry)

	for {
		skip_newlines(p)
		tok := current_token(p)

		// Detener si encontramos una nueva sección o palabra clave
		if tok.kind == .LeftSquare || tok.kind == .EOF {
			break
		}

		// Verificar si esta es una línea de entrada (clave: valor)
		if tok.kind == .Identifier {
			next := peek_token(p)
			if next.kind == .Colon {
				// Verificar si esta es una declaración de selector o plantilla
				next2 := peek_token(p, 2)
				if next2.kind == .Keyword &&
				   (next2.value == "selector" || next2.value == "template") {
					// Esta es una nueva selector/plantilla, detener aquí
					break
				}

				key := tok.value
				advance_parser(p) // omitir clave
				advance_parser(p) // omitir dos puntos

				skip_whitespace_tokens(p)

				values := make([dynamic]string)

				// Verificar si el valor es un arreglo [a, b, c]
				if current_token(p).kind == .LeftSquare {
					advance_parser(p) // omitir '['

					for {
						skip_whitespace_tokens(p)
						tok := current_token(p)

						if tok.kind == .RightSquare {
							advance_parser(p)
							break
						}

						if tok.kind == .Identifier || tok.kind == .String {
							append(&values, tok.value)
							advance_parser(p)
						} else if tok.kind == .Comma {
							advance_parser(p)
						} else {
							break
						}
					}
				} else {
					// Valor único
					value := parse_value(p)
					if value != "" {
						append(&values, value)
					}
				}

				append(&entries, types.TemplateEntry{key = key, values = values})
				skip_newlines(p)
			} else {
				break
			}
		} else {
			break
		}
	}

	// Verificar si la variable ya existe
	if name in p.config.variables {
		fmt.println("variable ya existe:", name)
		return
	}

	p.config.variables[name] = types.Variable {
		name = name,
		kind = .Template,
		value = types.Template{pattern = pattern, entries = entries},
	}
}

// Analizar sección de objetivo: [windows]
parse_target :: proc(p: ^Parser) {
	// El token actual es '['
	advance_parser(p)

	tok := current_token(p)
	if tok.kind != .Identifier && tok.kind != .Keyword {
		return
	}

	target_name := tok.value
	advance_parser(p)

	if !expect(p, .RightSquare) {
		return
	}

	skip_newlines(p)

	target := types.Target{}
	current_block := ""

	for {
		skip_newlines(p)
		tok := current_token(p)

		// Detener en la siguiente sección o EOF
		if tok.kind == .LeftSquare || tok.kind == .EOF {
			break
		}

		// Verificar palabras clave de bloque: build:, run:, copy:, clean:
		if tok.kind == .Keyword || tok.kind == .Identifier {
			next := peek_token(p)

			if next.kind == .Colon {
				block_name := tok.value
				advance_parser(p) // omitir nombre de bloque
				advance_parser(p) // omitir dos puntos

				skip_whitespace_tokens(p)

				// Verificar si hay un comando en la misma línea
				cmd := parse_value(p)

				if cmd != "" {
					append_command(&target, block_name, cmd)
					current_block = ""
				} else {
					current_block = block_name
				}

				skip_newlines(p)
			} else if current_block != "" {
				// Esta es una línea de comando en el bloque actual
				cmd := read_until_newline(p)
				if cmd != "" {
					append_command(&target, current_block, cmd)
				}
				skip_newlines(p)
			} else {
				break
			}
		} else if tok.kind == .At {
			// Comando que comienza con @
			cmd := read_until_newline(p)
			if current_block != "" && cmd != "" {
				append_command(&target, current_block, cmd)
			}
			skip_newlines(p)
		} else {
			break
		}
	}

	p.config.targets[target_name] = target
}

// Función principal de análisis
parse :: proc(p: ^Parser) -> types.Config {
	for {
		skip_newlines(p)
		skip_whitespace_tokens(p)

		tok := current_token(p)

		if tok.kind == .EOF {
			break
		}

		if tok.kind == .Comment {
			advance_parser(p)
			continue
		}

		// Verificar diferentes tipos de declaraciones
		if tok.kind == .Keyword {
			switch tok.value {
			case "default":
				// default: all
				advance_parser(p)
				if expect(p, .Colon) {
					skip_whitespace_tokens(p)
					p.config.default_target = parse_value(p)
				}

			case "flags":
				parse_flags(p)
			case "env":
				parse_env_variable(p)
			case:
				// Verificar si es un selector o plantilla
				next := peek_token(p)
				if next.kind == .Colon {
					next2 := peek_token(p, 2)
					if next2.kind == .Keyword {
						if next2.value == "selector" {
							parse_selector(p)
						} else if next2.value == "template" {
							parse_template(p)
						} else {
							advance_parser(p)
						}
					} else {
						advance_parser(p)
					}
				} else {
					advance_parser(p)
				}
			}
		} else if tok.kind == .Identifier {
			// Verificar qué sigue
			next := peek_token(p)

			if next.kind == .Equal {
				// Asignación de variable
				parse_variable(p)
			} else if next.kind == .Colon {
				// Podría ser selector, plantilla o bloque de objetivo
				next2 := peek_token(p, 2)
				if next2.kind == .Keyword {
					if next2.value == "selector" {
						parse_selector(p)
					} else if next2.value == "template" {
						parse_template(p)
					} else {
						advance_parser(p)
					}
				} else {
					advance_parser(p)
				}
			} else {
				advance_parser(p)
			}
		} else if tok.kind == .LeftSquare {
			// Sección de objetivo
			parse_target(p)
		} else {
			advance_parser(p)
		}

		skip_newlines(p)
	}

	return p.config
}

// ============================================================================
// PUBLIC API
// ============================================================================

load_config_new :: proc(path: string) -> types.Config {
	data, err := os.read_entire_file(path)
	if err == false {
		fmt.printf("No se pudo leer el archivo %s\n", path)
		os.exit(1)
	}

	input := string(data)
	tokens := tokenize(input)

	parser := make_parser(tokens[:], input)
	config := parse(&parser)

	return config
}
