#+feature dynamic-literals
package main

import "core:fmt"

import "core:testing"
import "preprocesor"
import "types"

@(test)
test_command_now_year :: proc(t: ^testing.T) {
	command := "{now(YYYY)}"
	config := types.Config{}
	preprocesor.expand_line(&command, &config)
	output, _ := preprocesor.resolve_funtion("now", {"YYYY"})
	testing.expect(t, output == command)
}

@(test)
test_command_now_hour :: proc(t: ^testing.T) {
	command := "{now(hh)}"
	config := types.Config{}
	preprocesor.expand_line(&command, &config)
	output, _ := preprocesor.resolve_funtion("now", {"hh"})
	testing.expect(t, output == command)
}

@(test)
test_command_now :: proc(t: ^testing.T) {
	command := "{now()}"
	config := types.Config{}
	preprocesor.expand_line(&command, &config)
	output, _ := preprocesor.resolve_funtion("now", {})
	testing.expect(t, output[:16] == command[:16])
}

@(test)
test_current_group :: proc(t: ^testing.T) {
	command := "{path_selector}"
	config := types.Config{}
	config.current_group = "windows"
	config.variables["path_selector"] = types.Variable {
		name = "path_selector",
		kind = .Selector,
		value = types.Selector {
			source = "group",
			mapping = {"windows" = "build/windows", "linux" = "build/linux"},
			default = "",
		},
	}
	preprocesor.expand_line(&command, &config)
	testing.expect(t, "build/windows" == command)
}

@(test)
test_variable_selector_current_flag :: proc(t: ^testing.T) {
	command := "{flag}"
	config := types.Config{}
	config.current_flag = "release"
	config.variables["flag"] = types.Variable {
		name = "flag",
		kind = .Selector,
		value = types.Selector {
			source = "flags",
			mapping = {"debug" = "-debug", "release" = "-release"},
			default = "",
		},
	}
	preprocesor.expand_line(&command, &config)
	testing.expect(t, "-release" == command)
}

@(test)
test_variable_template :: proc(t: ^testing.T) {
	command := "{collections}"
	config := types.Config{}
	config.variables["collections"] = types.Variable {
		name = "collections",
		kind = .Template,
		value = types.Template {
			pattern = "-collections:key:a1",
			entries = {
				types.TemplateEntry{key = "lib1", values = {"src/lib"}},
				types.TemplateEntry{key = "lib2", values = {"src/lib2"}},
			},
		},
	}
	preprocesor.expand_line(&command, &config)
	testing.expect(t, "-collections:lib1:src/lib -collections:lib2:src/lib2" == command)
}

@(test)
test_variable_template_selection :: proc(t: ^testing.T) {
	command := "{collections[lib2]}"
	config := types.Config{}
	config.variables["collections"] = types.Variable {
		name = "collections",
		kind = .Template,
		value = types.Template {
			pattern = "-collections:key:a1",
			entries = {
				types.TemplateEntry{key = "lib1", values = {"src/lib"}},
				types.TemplateEntry{key = "lib2", values = {"src/lib2"}},
			},
		},
	}
	preprocesor.expand_line(&command, &config)
	testing.expect(t, "-collections:lib2:src/lib2" == command)
}

/*@(test)
test_command :: proc(t: ^testing.T) {
	command := "{cmd@cmd /c echo hola}"
	config := types.Config{}
	preprocesor.expand_line(&command, &config)
	fmt.println("comando:", command)
	testing.expect(t, "hola" == command)
	}*/

