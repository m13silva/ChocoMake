package utils

import "../types"
import "core:fmt"
import "core:text/regex"


split_cmd :: proc(line: string) -> []string {
	//"([^"]*)"|(\S+)
	//"[^"]*"|\S+
	pattern, _ := regex.create_iterator(line, `"[^"]*"|\S+`)
	result := [dynamic]string{}
	for match in regex.match(&pattern) {
		append(&result, match.groups[0])
	}
	return result[:]
}

print_variables_debug :: proc(variables: map[string]types.Variable) {
	fmt.println("=== DEBUG: Variables ===")
	if len(variables) == 0 {
		fmt.println("  (empty)")
		return
	}

	for name, var in variables {
		fmt.printf("  [%s] kind=%v\n", name, var.kind)

		switch v in var.value {
		case string:
			fmt.printf("    value: \"%s\"\n", v)

		case types.Selector:
			fmt.printf("    source: \"%s\"\n", v.source)
			fmt.printf("    default: \"%s\"\n", v.default)
			fmt.println("    mapping:")
			if len(v.mapping) == 0 {
				fmt.println("      (empty)")
			} else {
				for key, val in v.mapping {
					fmt.printf("      %s -> %s\n", key, val)
				}
			}

		case types.Template:
			fmt.printf("    pattern: \"%s\"\n", v.pattern)
			fmt.println("    entries:")
			if len(v.entries) == 0 {
				fmt.println("      (empty)")
			} else {
				for entry in v.entries {
					fmt.printf("      [%s]: ", entry.key)
					if len(entry.values) == 0 {
						fmt.println("[]")
					} else {
						fmt.print("[")
						for val, i in entry.values {
							if i > 0 do fmt.print(", ")
							fmt.printf("\"%s\"", val)
						}
						fmt.println("]")
					}
				}
			}
		}
		fmt.println()
	}
	fmt.println("========================")
}
