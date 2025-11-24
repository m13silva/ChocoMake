package parser

import "../types"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:text/regex"

load_config :: proc(path: string) -> types.Config {
	data, err := os.read_entire_file(path)
	if err == false {
		fmt.printf("No se pudo leer el archivo %s\n", path)
		os.exit(1)
	}

	lines := strings.split_lines(string(data))
	config: types.Config
	config.targets = make(map[string]types.Target)

	current := ""
	current_block := "" // "build", "run", etc.

	for raw_line in lines {
		// Quitar \r\n del final
		line := strings.trim_right(raw_line, "\r\n")
		if line == "" {
			continue
		}

		// Ignorar comentarios (aunque tengan espacios antes)
		left_trim := strings.trim_left_space(line)
		if strings.has_prefix(left_trim, "#") {
			continue
		}

		if strings.has_prefix(line, "flags") {
			parts, _ := strings.split_n(line, ":", 2)
			if len(parts) > 1 {
				inside := strings.trim(parts[1], " []")
				items := strings.split(inside, ",")
				for i in 0 ..< len(items) - 1 {
					items[i] = strings.trim_space(items[i])
				}
				config.flags = items
			}
			continue
		}
		// variables env
		if strings.contains(line, "env.") {
			envparts, _ := strings.split_n(line, ".", 2)
			name := envparts[1]
			if name in config.variables {
				fmt.println("variable ya existe:", name)
				continue
			}
			envvalue := os.get_env(name)
			if envvalue != "" {
				config.variables[name] = types.Variable {
					name  = name,
					kind  = .Normal,
					value = envvalue,
				}
			}
		}
		//VARIABLE NORMAL  (name = "Grafito")
		if strings.contains(line, "=") && !strings.contains(line, ":") {
			parts, _ := strings.split_n(line, "=", 2)
			name := strings.trim_space(parts[0])
			if name in config.variables {
				fmt.println("variable ya existe:", name)
				continue
			}

			value := strings.trim_space(parts[1])
			value = strings.trim(value, "\"")
			value, _ = strings.replace_all(value, "\\\"", "\"")

			if undefinedType(&value) {
				config.variables[name] = types.Variable {
					name  = name,
					kind  = .Reference,
					value = value,
				}
			} else {
				config.variables[name] = types.Variable {
					name  = name,
					kind  = .Normal,
					value = value,
				}
			}
			continue
		}

		// SELECTOR
		if strings.contains(line, ": selector") {
			parts := strings.split(line, " ")
			name := strings.trim_suffix(strings.trim_space(parts[0]), ":")
			source := "flags"
			//fmt.println("parts:", parts)
			if len(parts) > 2 {
				source = strings.trim_space(parts[2])
			}

			mapping := make(map[string]string)

			// leer líneas siguientes
			for i := index_of(lines, raw_line) + 1; i < len(lines); i += 1 {
				nxt := strings.trim_space(lines[i])
				if nxt == "" || strings.has_prefix(nxt, "[") {break}
				if strings.contains(nxt, ":") == false {break}
				kv, _ := strings.split_n(nxt, ":", 2)
				key := strings.trim_space(kv[0])
				val := strings.trim_space(kv[1])
				mapping[key] = val
			}

			config.variables[name] = types.Variable {
				name = name,
				kind = .Selector,
				value = types.Selector{source = source, mapping = mapping},
			}
			continue
		}

		//TEMPLATE
		if strings.contains(line, ": template") {
			parts := strings.split(line, " ")
			name := strings.trim_suffix(strings.trim_space(parts[0]), ":")
			pattern := parts[len(parts) - 1]

			entries := [dynamic]types.TemplateEntry{}
			for i := index_of(lines, raw_line) + 1; i < len(lines); i += 1 {
				nxt := strings.trim_space(lines[i])
				if nxt == "" || strings.has_prefix(nxt, "[") {break}
				if strings.contains(nxt, ": template") ||
				   strings.contains(nxt, ": selector") ||
				   strings.has_prefix(nxt, "[") ||
				   strings.has_suffix(nxt, ":") {
					break
				}
				if strings.has_prefix(nxt, "#") {continue}

				kv, _ := strings.split_n(nxt, ":", 2)
				key := strings.trim_space(kv[0])
				values := [dynamic]string{}


				if len(kv) > 1 {
					kv[1] = strings.trim_space(kv[1])
					if strings.has_prefix(kv[1], "[") && strings.has_suffix(kv[1], "]") {
						cut := strings.cut(kv[1], 1, len(kv[1]) - 2)
						split := strings.split(cut, ",")
						for s in split {
							append(&values, s)
						}
					} else {
						append(&values, strings.trim(kv[1], "\""))
					}
				}
				append(&entries, types.TemplateEntry{key = key, values = values})
			}

			// detectar campos del patrón
			colon_parts := strings.split(pattern, ":")
			/*fields := [dynamic]string{}
			for i in 1 ..< len(colon_parts) - 1 {
				append(&fields, colon_parts[i])
				}*/


			config.variables[name] = types.Variable {
				name = name,
				kind = .Template,
				value = types.Template {
					pattern = pattern, /*fields = fields,*/
					entries = entries,
				},
			}
			continue
		}
		// Normalizar: sin espacios a la izquierda
		line = left_trim
		//Sección [target]
		if strings.has_prefix(line, "[") {
			current = strings.trim(line, "[]")
			config.targets[current] = types.Target{}
			current_block = ""
			continue
		}

		//Clave: valor  (build:, run:, copy:, clean:, default:, etc.)
		//fmt.println("linea:", line)
		if strings.contains(line, ":") {
			parts, _ := strings.split_n(line, ":", 2)
			key := strings.trim_space(parts[0])
			if strings.count(key, " ") > 0 {
				if current_block != "" && current != "" {
					cmd := strings.trim_space(line)
					t := config.targets[current]
					append_command(&t, current_block, cmd)
					config.targets[current] = t
					continue
				}
			}
			value := ""
			if len(parts) > 1 {
				value = strings.trim_space(parts[1])
			}
			// Caso especial: default: all
			if key == "default" {
				config.default_target = value
				current_block = ""
				continue
			}

			// Es una clave normal de target (build, run, copy, clean)
			t := config.targets[current]
			current_block = key

			// build: algo en la misma línea
			if value != "" {
				append_command(&t, key, value)
				current_block = "" // cerramos el bloque porque ya no hay más líneas debajo
			}

			config.targets[current] = t
			continue
		}

		// 🔹 Si no tiene ':' ni '[', y estamos dentro de un bloque → es un comando del bloque
		if current_block != "" && current != "" {
			cmd := strings.trim_space(line)
			t := config.targets[current]
			append_command(&t, current_block, cmd)
			config.targets[current] = t
			continue
		}

		// 🔹 Si llega aquí, es una línea que no encaja en nada
		current_block = ""
	}
	//fmt.printfln("flags:", config.flags)
	//fmt.printfln("variables:", config.variables)
	//fmt.println(expand_template(config.variables["multiple"].value.(types.Template)))
	//fmt.println(expand_template(config.variables["collections"].value.(types.Template)))
	//expand_line("odin build src {win_flag} {collections}", &config)
	return config
}

undefinedType :: proc(value: ^string) -> bool {
	pattern, _ := regex.create_iterator(value^, `\{([^}]+)\}`)
	_, _, ok := regex.match(&pattern)
	return ok
}

index_of :: proc(lines: []string, text: string) -> int {
	for l, i in lines {
		if l == text {
			return i
		}
	}
	return -1
}

append_command :: proc(t: ^types.Target, key, cmd: string) {
	switch key {
	case "build":
		append(&t.build, cmd)
	case "run":
		append(&t.run, cmd)
	case "copy":
		append(&t.copy, cmd)
	case "clean":
		append(&t.clean, cmd)
	}
}

