package preprocesor

import "../types"
import "../utils"
import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:slice"
import "core:strings"
import "core:text/regex"
import "core:time"

expand_line :: proc(line: ^string, cfg: ^types.Config) {
	pattern, _ := regex.create_iterator(line^, `\{([^}]+)\}`)
	//fmt.println("[GRUPO]:", cfg.current_group)
	for match in regex.match(&pattern) {
		if len(match.groups) > 1 {
			value := match.groups[1]
			full := match.groups[0]
			//fmt.println("value:", value)
			//fmt.println("full:", full)
			replace, _ := expand_var(value, cfg, line, false)
			line^, _ = strings.replace_all(line^, full, replace)
		}
	}
}

expand_line_undefined :: proc(line: ^string, cfg: ^types.Config) -> (string, string) {
	pattern, _ := regex.create_iterator(line^, `\{([^}]+)\}`)
	final_list := map[string]string{}
	for match in regex.match(&pattern) {
		if len(match.groups) > 1 {
			value := match.groups[1]
			full := match.groups[0]
			//fmt.println("value:", value)
			//fmt.println("full:", full)
			result, replace := expand_var(value, cfg, line, true)
			if replace {
				line^, _ = strings.replace_all(line^, full, result)
			} else {
				final_list[full] = result
			}
		}
	}

	final := line^
	if len(final_list) > 0 {
		//final = line^
		for key, value in final_list {
			final, _ = strings.replace_all(final, key, value)
		}
	} else {
		//delete(final)
	}
	return line^, final
}

expand_var :: proc(
	expr: string,
	cfg: ^types.Config,
	line: ^string,
	undefined: bool,
) -> (
	result: string,
	replace: bool,
) {
	// Soporte para {var[key]}
	name := expr
	filters := []string{}
	//fmt.println("exp:", name)
	if strings.contains(expr, "[") && strings.contains(expr, "]") {
		parts, _ := strings.split_n(expr, "[", 2)
		//fmt.println("parts:", parts)
		name = strings.trim_space(parts[0])
		//fmt.println("name:", name)
		filter := strings.trim(parts[1], "[]")
		//fmt.println("filter:", filter)
		filters = strings.split(filter, ",")
	} else if (strings.contains(expr, "(") && strings.contains(expr, ")")) {
		parts, _ := strings.split_n(expr, "(", 2)
		//fmt.println("metodo:", parts)
		name = strings.trim_space(parts[0])
		//fmt.println("nombre:", name)
		if parts[1] != ")" {
			argumentos := strings.trim(parts[1], "()")
			//fmt.println("argumento:", argumentos)
			filters = strings.split(argumentos, ",")
		}
	}

	//fmt.println("filters:", filters)

	/*fmt.println(
		"nombre variable:[",
		name,
		"]undefinned:",
		undefined,
		"kind:",
		cfg.variables[name].kind,
		)*/
	if name not_in cfg.variables || cfg.variables[name].kind != .Reference {
		value, ok := resolve_funtion(name, filters)
		if (ok) {
			return value, true
		}

		val_comand, okc := resolve_command(name)
		if okc {
			//fmt.println("final comand:", val_comand)
			return val_comand, true
		}
	}


	if v, ok := cfg.variables[name]; ok {
		#partial switch v.kind {
		case .Normal:
			//fmt.println("var return:", v.value.(string))
			return v.value.(string)
		case .Template:
			{
				tmpl := v.value.(types.Template)
				return expand_template(tmpl, filters), true
			}
		case .Selector:
			sel := v.value.(types.Selector)
			if undefined && sel.source == "group" {
				return resolve_selector(sel, cfg), false
			} else {
				return resolve_selector(sel, cfg), true
			}

		case .Reference:
			und := cfg.variables[name].value.(string)
			//if undefined {
			//fmt.println("value undefine", und)
			replace, final := expand_line_undefined(&und, cfg)
			//fmt.println("final replace?:", final)
			//fmt.println("replace:", replace)
			if final == replace {
				cfg.variables[name] = types.Variable {
					name  = name,
					kind  = .Normal,
					value = replace,
				}
				valuefinal := cfg.variables[name].value.(string)
			} else {
				cfg.variables[name] = types.Variable {
					name  = name,
					kind  = .Reference,
					value = replace,
				}
				valuefinal := cfg.variables[name].value.(string)
			}

			//expand_line(line, cfg)
			if undefined {
				return final, true
			} else {
				return final, false
			}
		/*} else {
				expand_line_undefined(&und.value, cfg)
			}*/
		}
	}

	return fmt.tprintf("error no se resuelve: {0}", expr), false
}

resolve_command :: proc(exp: string) -> (string, bool) {
	if strings.contains(exp, "cmd@") {
		//fmt.println("command:", exp)
		cmd := strings.cut(exp, 4, len(exp))
		//fmt.println("cmd2:", cmd)

		commands := utils.split_cmd(cmd)
		//fmt.println("commands:", commands)
		exec, _ := utils.exec_util2(commands)
		return exec, true
	}
	return "", false
}


resolve_funtion :: proc(funcion: string, args: []string) -> (string, bool) {
	//fmt.println("function:", funcion)
	switch funcion {
	case "now":
		//fmt.println("ejecutando now")
		now := time.now()
		if len(args) == 1 {
			//fmt.println("tiene argumentos:", args, "el tiempo es:", now)
			return resolve_time(args[0], now), true
		} else {
			//fmt.println("no tiene argumentos:", now)
			return fmt.tprintf("%v", now), true
		}
	case "read_file":
		if len(args) == 1 && args[0] != "" {
			if os.exists(args[0]) {
				data, ok := os.read_entire_file(args[0])
				if ok {
					return string(data), true
				}
			}
		}
	}
	return "", false
}

resolve_time :: proc(format: string, t: time.Time) -> string {
	out := format
	h, min, s := time.clock(t)
	year, month, day := time.date(t)

	out, _ = strings.replace_all(out, "YYYY", fmt.tprintf("%04d", year))
	out, _ = strings.replace_all(out, "MM", fmt.tprintf("%02d", month))
	out, _ = strings.replace_all(out, "DD", fmt.tprintf("%02d", day))

	out, _ = strings.replace_all(out, "hh", fmt.tprintf("%02d", h))
	out, _ = strings.replace_all(out, "mm", fmt.tprintf("%02d", min))
	out, _ = strings.replace_all(out, "ss", fmt.tprintf("%02d", s))

	return out
}


resolve_selector :: proc(t: types.Selector, cfg: ^types.Config) -> string {
	switch t.source {
	case "flags":
		//fmt.println("flag current:", cfg.current_flag)
		//fmt.println("flags:", cfg.flags)
		//fmt.println("map:", t.mapping)
		if slice.contains(cfg.flags, cfg.current_flag) && cfg.current_flag in t.mapping {
			fmt.println(t.mapping[cfg.current_flag])
			return t.mapping[cfg.current_flag]
		} else {
			return t.mapping[cfg.flags[0]]
		}
	case "group":
		if cfg.current_group in t.mapping {
			//fmt.println("group:", cfg.current_group)
			//fmt.println("mapping:", t.mapping[cfg.current_group])
			return t.mapping[cfg.current_group]
		}
	}
	return t.default
}


expand_template :: proc(t: types.Template, filter: []string) -> string {
	b := strings.Builder{}
	strings.builder_init(&b)

	// key : []string
	for entry in t.entries {

		if len(filter) > 0 && !slice.contains(filter, entry.key) {
			continue
		}

		expanded := t.pattern
		expanded, _ = strings.replace_all(expanded, "key", entry.key)

		for val, i in entry.values {
			placeholder := fmt.tprintf("a%d", (i + 1))
			expanded, _ = strings.replace_all(expanded, placeholder, val)
		}

		strings.write_string(&b, strings.concatenate({expanded, " "}))
	}

	fmt.println(strings.trim_space(strings.to_string(b)))

	return strings.trim_space(strings.to_string(b))
}

