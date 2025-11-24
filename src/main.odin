package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:terminal/ansi"
import "core:time"
import "core:unicode/utf8"
import "preprocesor"
import "utils"

import "executor"
import "parser"
import "types"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
	args := os.args[1:]

	if len(args) < 2 {
		fmt.println("Uso: chocomake <comando> [target]")
		return
	}
	ascii_art := `
  /$$$$$$  /$$                                     /$$      /$$           /$$
 /$$__  $$| $$                                    | $$$    /$$$          | $$
| $$  \__/| $$$$$$$   /$$$$$$   /$$$$$$$  /$$$$$$ | $$$$  /$$$$  /$$$$$$ | $$   /$$  /$$$$$$
| $$      | $$__  $$ /$$__  $$ /$$_____/ /$$__  $$| $$ $$/$$ $$ |____  $$| $$  /$$/ /$$__  $$
| $$      | $$  \ $$| $$  \ $$| $$      | $$  \ $$| $$  $$$| $$  /$$$$$$$| $$$$$$/ | $$$$$$$$
| $$    $$| $$  | $$| $$  | $$| $$      | $$  | $$| $$\  $ | $$ /$$__  $$| $$_  $$ | $$_____/
|  $$$$$$/| $$  | $$|  $$$$$$/|  $$$$$$$|  $$$$$$/| $$ \/  | $$|  $$$$$$$| $$ \  $$|  $$$$$$$
 \______/ |__/  |__/ \______/  \_______/ \______/ |__/     |__/ \_______/|__/  \__/ \_______/
                                                                                       v0.1.0
`


	/*fmt.printfln(
		strings.concatenate(
			{ansi.CSI, ansi.FG_MAGENTA, ansi.SGR, ascii_art, ansi.CSI, ansi.RESET, ansi.SGR},
		),
		)*/
	for c in ascii_art {
		color := ansi.CSI + ansi.RESET + ansi.SGR

		switch c {
		case '$':
			color = ansi.CSI + ansi.FG_MAGENTA + ansi.SGR
		case '/', '\\', '|', '_':
			color = ansi.CSI + ansi.FG_BRIGHT_MAGENTA + ansi.SGR
		case:
			color = ansi.CSI + ansi.FG_BRIGHT_BLACK + ansi.SGR
		}
		str_bytes, str_len := utf8.encode_rune(c)
		str := string(str_bytes[:str_len])
		fmt.printf(strings.concatenate({color, str, ansi.CSI + ansi.RESET + ansi.SGR}))
	}

	command := args[0]
	target_name := ""
	if len(args) > 1 {
		target_name = args[1]
	}

	parallel_mode := false
	if len(args) > 2 && args[2] == "-parallel" {
		fmt.println("paralelo")
		parallel_mode = true
	}

	flag_value := ""
	for arg in os.args {
		if strings.has_prefix(arg, "-f:") {
			flag_value = strings.trim_prefix(arg, "-f:")
			break
		}
	}

	//config := parser.load_config("ChocoMake")
	// Try multiple config filenames
	config_filename := ""
	possible_names := []string{"ChocoMake", "chocomake", "chocofile"}
	for name in possible_names {
		if os.exists(name) {
			config_filename = name
			break
		}
	}
	if config_filename == "" {
		fmt.println(
			"Error: No se encontró archivo de configuración (ChocoMake, chocomake, o chocofile)",
		)
		return
	}
	config := parser.load_config_new(config_filename)
	config.variables["commit_hash_short"] = types.Variable {
		name  = "commit_hash_short",
		kind  = .Reference,
		value = "{cmd@git rev-parse --short HEAD}",
	}
	config.variables["commit_hash"] = types.Variable {
		name  = "commit_hash",
		kind  = .Reference,
		value = "{cmd@git rev-parse HEAD}",
	}
	config.current_flag = flag_value
	if target_name == "" {
		target_name = config.default_target
	}

	//now := time.now()
	//fmt.println("time", now)
	executor.run_command(&config, target_name, command, parallel_mode)
	//test := "wsl -e sh -c \"odin build src -out:{path_selector}/{name} -target:linux_amd64 {output}\""
	//preprocesor.expand_line(&test, &config)
	//fmt.println("test:", test)
	//fmt.println(utils.split_cmd(test))
}
