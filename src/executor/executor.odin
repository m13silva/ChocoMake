package executor

import "../preprocesor"
import "../third_party/jobs"
import "../types"
import "../utils"
import "core:fmt"
import "core:io"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:terminal/ansi"
import "core:text/regex"

Job_Line :: struct {
	config:      ^types.Config,
	target_name: string,
	command:     string,
	line:        string,
}

File_Operation :: enum {
	Copy,
	Move,
	Delete,
}


run_command :: proc(config: ^types.Config, target_name, command: string, parallel_mode := false) {
	target, ok := config.targets[target_name]
	if !ok {
		fmt.printf("Target '%s' no encontrado\n", target_name)
		return
	}
	//utils.print_variables_debug(config.variables)
	fmt.printf("Ejecutando %s en %s...\n", command, target_name)
	config.current_group = target_name

	lines: [dynamic]string

	switch command {
	case "build":
		lines = target.build
	case "run":
		lines = target.run
	case "copy":
		lines = target.copy
	case "clean":
		lines = target.clean
	}
	//fmt.println("lineas:", lines)
	if parallel_mode {
		fmt.println("jobs")
		jobs.initialize()
		g: jobs.Group

		for line in lines {
			line := strings.trim_space(line)
			if line == "" {continue}

			data := new(Job_Line)
			data.config = config
			data.target_name = target_name
			data.command = command
			data.line = line
			jobs.dispatch(.Medium, jobs.make_job(&g, data, exec_job))
		}

		jobs.wait(&g)
		jobs.shutdown()
		return
	}

	for line in lines {
		line := strings.trim_space(line)
		if line == "" {
			continue
		}

		// Detectar operaciones de archivos (orden importante: <-> antes de ->)
		if strings.contains(line, "<->") {
			// COPY operation
			handle_file_operation(line, config, .Copy)
			continue
		} else if strings.contains(line, "->") {
			// MOVE operation
			handle_file_operation(line, config, .Move)
			continue
		} else if strings.has_prefix(line, "delete ") {
			// DELETE operation
			handle_delete_operation(line, config)
			continue
		}

		// Si la línea comienza con @call
		if strings.has_prefix(line, "@call") {
			parts := strings.fields(line)
			if len(parts) < 2 {
				fmt.println("Error: uso incorrecto de @call")
				continue
			}

			next_target := parts[1]
			next_command := command

			// Soporte para @call target:otro_comando
			if strings.contains(next_target, ":") {
				tparts, _ := strings.split_n(next_target, ":", 2)
				next_target = tparts[0]
				if len(tparts) > 1 {
					next_command = tparts[1]
				}
			}

			run_command(config, next_target, next_command)
			continue
		}

		if strings.has_prefix(line, "@hook") {
			parts := strings.fields(line)
			if len(parts) < 2 {
				fmt.println("Error: uso incorrecto de @hook")
				continue
			}
			next_command := parts[1]
			run_command(config, target_name, next_command)
			continue
		}


		// Ejecutar comando normal
		ok = exec(config, line)
		if !ok {
			fmt.println(
				"[",
				ansi.CSI +
				ansi.FG_RED +
				ansi.SGR +
				"Error" +
				ansi.CSI +
				ansi.RESET +
				ansi.SGR +
				"]",
				command,
				target_name,
			)
			break
		}
	}
}

exec_job :: proc(ctx: ^Job_Line) {
	job := ctx // convertir el puntero crudo de vuelta a tipo Job_Line
	fmt.println("exec:", jobs.current_thread_index())

	line := strings.trim_space(job.line)
	if line == "" {return}

	// Detectar operaciones de archivos (orden importante: <-> antes de ->)
	if strings.contains(line, "<->") {
		// COPY operation
		handle_file_operation(line, job.config, .Copy)
		return
	} else if strings.contains(line, "->") {
		// MOVE operation
		handle_file_operation(line, job.config, .Move)
		return
	} else if strings.has_prefix(line, "delete ") {
		// DELETE operation
		handle_delete_operation(line, job.config)
		return
	}

	// Si es una llamada a otro target
	if strings.has_prefix(line, "@call") {
		parts := strings.fields(line)
		if len(parts) < 2 {return}

		next_target := parts[1]
		next_command := job.command

		if strings.contains(next_target, ":") {
			tparts, _ := strings.split_n(next_target, ":", 2)
			next_target = tparts[0]
			if len(tparts) > 1 {
				next_command = tparts[1]
			}
		}

		run_command(job.config, next_target, next_command, false)
		return
	}

	// Comando normal (odin, echo, etc.)
	exec(job.config, line)
}


copy_file :: proc(src_path, dst_path: string) -> (ok: bool) {
	// Abrir archivo fuente (solo lectura)
	src_handle, err := os.open(src_path, os.O_RDONLY)
	if err != io.Error.None {
		fmt.printf("Error al abrir fuente '%s': %v\n", src_path, err)
		return false
	}
	defer os.close(src_handle)

	// Crear carpeta destino si no existe
	dir := filepath.dir(dst_path)
	_ = os.make_directory(dir, 0o755)

	// Crear archivo destino (escritura/truncar si existe)
	dst_handle, err2 := os.open(dst_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err2 != io.Error.None {
		fmt.printf("Error al abrir destino '%s': %v\n", dst_path, err2)
		os.close(src_handle)
		return false
	}
	defer os.close(dst_handle)

	// Convertir los handles a streams para usarlos con io.copy
	src_stream := os.stream_from_handle(src_handle)
	dst_stream := os.stream_from_handle(dst_handle)

	// Copiar datos
	_, copy_err := io.copy(dst_stream, src_stream)
	if copy_err != io.Error.None {
		fmt.printf("Error al copiar '%s' → '%s': %v\n", src_path, dst_path, copy_err)
		return false
	}

	fmt.printf("Copiado %s ↔ %s\n", src_path, dst_path)
	return true
}

move_file :: proc(src_path, dst_path: string) -> (ok: bool) {
	// Verificar que el archivo fuente existe
	if !os.exists(src_path) {
		fmt.printf("Error: archivo fuente '%s' no existe\n", src_path)
		return false
	}

	// Crear directorio destino si no existe
	dir := filepath.dir(dst_path)
	_ = os.make_directory(dir, 0o755)

	// Intentar rename primero (más rápido si están en el mismo filesystem)
	err := os.rename(src_path, dst_path)
	if err == os.ERROR_NONE {
		fmt.printf("Movido %s → %s\n", src_path, dst_path)
		return true
	}

	// Si rename falla, hacer copy + delete
	if copy_file(src_path, dst_path) {
		os.remove(src_path)
		fmt.printf("Movido %s → %s\n", src_path, dst_path)
		return true
	}

	return false
}

delete_file :: proc(path: string) -> (ok: bool) {
	if !os.exists(path) {
		fmt.printf("Advertencia: archivo '%s' no existe\n", path)
		return false
	}

	err := os.remove(path)
	if err == os.ERROR_NONE {
		fmt.printf("Eliminado: %s\n", path)
		return true
	} else {
		fmt.printf("Error al eliminar '%s': %v\n", path, err)
		return false
	}
}

delete_directory :: proc(path: string) -> (ok: bool) {
	if !os.exists(path) {
		fmt.printf("Advertencia: directorio '%s' no existe\n", path)
		return false
	}

	// Usar os2.remove_all para eliminar recursivamente
	err := os2.remove_all(path)
	if err == nil {
		fmt.printf("Eliminado directorio: %s\n", path)
		return true
	} else {
		fmt.printf("Error al eliminar directorio '%s': %v\n", path, err)
		return false
	}
}

handle_glob_operation :: proc(pattern: string, dst: string, op: File_Operation) {
	// Usar filepath.glob() para expandir el patrón
	matches, err := filepath.glob(pattern)
	if err != nil {
		fmt.printf("Error al expandir patrón '%s': %v\n", pattern, err)
		return
	}

	if len(matches) == 0 {
		fmt.printf("Advertencia: patrón '%s' no coincide con ningún archivo\n", pattern)
		return
	}

	// Crear directorio destino si no existe
	_ = os.make_directory(dst, 0o755)

	for match in matches {
		filename := filepath.base(match)
		dst_path := filepath.join({dst, filename})

		switch op {
		case .Copy:
			copy_file(match, dst_path)
		case .Move:
			move_file(match, dst_path)
		case .Delete:
		// No debería llegar aquí
		}
	}
}

delete_glob :: proc(pattern: string) {
	matches, err := filepath.glob(pattern)
	if err != nil {
		fmt.printf("Error al expandir patrón '%s': %v\n", pattern, err)
		return
	}

	if len(matches) == 0 {
		fmt.printf("Advertencia: patrón '%s' no coincide con ningún archivo\n", pattern)
		return
	}

	for match in matches {
		delete_file(match)
	}
}

handle_file_operation :: proc(line: string, config: ^types.Config, op: File_Operation) {
	// Expandir variables {path_selector}, etc.
	expanded_line := line
	pattern, _ := regex.create_iterator(line, `\{([^}]+)\}`)
	_, _, ok := regex.match(&pattern)
	if ok {
		preprocesor.expand_line(&expanded_line, config)
	}

	// Separar src y dst según el operador
	separator := op == .Copy ? "<->" : "->"
	parts, _ := strings.split_n(expanded_line, separator, 2)
	src := strings.trim_space(parts[0])
	dst := strings.trim_space(parts[1])

	// Detectar wildcards
	if strings.contains(src, "*") {
		handle_glob_operation(src, dst, op)
	} else {
		// Operación simple
		switch op {
		case .Copy:
			copy_file(src, dst)
		case .Move:
			move_file(src, dst)
		case .Delete:
		// No debería llegar aquí
		}
	}
}

handle_delete_operation :: proc(line: string, config: ^types.Config) {
	// Expandir variables
	expanded_line := line
	pattern, _ := regex.create_iterator(line, `\{([^}]+)\}`)
	_, _, ok := regex.match(&pattern)
	if ok {
		preprocesor.expand_line(&expanded_line, config)
	}

	// Extraer path después de "delete "
	path := strings.trim_space(strings.trim_prefix(expanded_line, "delete"))

	// Detectar wildcards
	if strings.contains(path, "*") {
		delete_glob(path)
	} else {
		// Detectar si es directorio o archivo
		file_info, err := os.stat(path)
		if err == os.ERROR_NONE {
			if file_info.is_dir {
				delete_directory(path)
			} else {
				delete_file(path)
			}
		} else {
			fmt.printf("Error: path '%s' no existe\n", path)
		}
	}
}


/*run_command :: proc(config: types.Config, target_name, command: string) {
	target, ok := config.targets[target_name]
	if !ok {
		fmt.printf("Target '%s' no encontrado\n", target_name)
		return
	}

	fmt.printf("Ejecutando %s en %s...\n", command, target_name)
	cmd := ""
	switch command {
	case "build":
		cmd = target.build
	case "run":
		cmd = target.run
	case "clean":
		for c in target.clean {exec(config, c)}
	case "copy":
		for c in target.copy {exec(config, c)}
	}

	fmt.printfln(cmd)

	/*if cmd != "" {
		exec(cmd)
		}*/
	// Ejecutar el comando principal
	if cmd != "" {
		// Si el comando contiene líneas múltiples, divídelas
		lines := strings.split_lines(cmd)
		for line in lines {
			line := strings.trim_space(line)
			if line == "" {continue}

			// Detectar @call
			if strings.has_prefix(line, "@call") {
				parts := strings.fields(line)
				if len(parts) < 2 {
					fmt.println("Error: uso incorrecto de @call")
					continue
				}

				next_target := parts[1]
				run_command(config, next_target, command)
				continue
			}

			exec(config, line)
		}
	}
	}*/

exec :: proc(config: ^types.Config, cmd: string) -> (ok: bool) {
	if cmd == "" {
		return false
	}
	//fmt.printf("→ %s\n", cmd)
	//command := "odin build src {win_flag} {collections[lib2]} -out:{path_selector}/{built_out}"
	//command := "odin build src {now(YYYY-MM-DD hh:mm:ss)} {commit_hash}"
	//command := "salida {now(YYYY-MM-DD hh:mm:ss)} {output}"
	command := cmd
	preprocesor.expand_line(&command, config)
	//fmt.println("command:", command)
	split := utils.split_cmd(command)
	//test := exec_util2({"odn", "build", "src"})
	//fmt.println("salida:", test)
	salida, state := utils.exec_util2(split)
	if state.exit_code == 0 {
		return true
	}
	return false
}

