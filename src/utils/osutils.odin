package utils

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:strings"

exec_util :: proc(comand: string) -> string {
	r, w, err := os2.pipe()
	if err != nil {
		fmt.println("pipe failed: %v")
	}
	defer os2.close(r)

	p: os2.Process; err2: os2.Error; {
		defer os2.close(w)
		p, err2 = os2.process_start(
			{command = {"pwsh.exe", "-NoProfile", "-Command", comand}, stdout = w},
		)
		if err2 != nil {
			fmt.printfln("process_start failed: %v", err2)
		}
	}
	output, _ := os2.read_entire_file(r, context.temp_allocator)
	_, _ = os2.process_wait(p)

	out := string(output)
	return out
}

exec_util2 :: proc(comands: []string) -> (string, os2.Process_State) {
	r, w, err := os2.pipe()
	if err != nil {
		fmt.println("pipe failed: %v")
	}
	defer os2.close(r)

	p: os2.Process; err2: os2.Error; {
		defer os2.close(w)
		p, err2 = os2.process_start({command = comands, stdout = w})
		if err2 != nil {
			fmt.printfln("process_start failed: %v", err2)
			return "", os2.Process_State{exit_code = 1}
		}
	}
	output, _ := os2.read_entire_file(r, context.allocator)
	state, error := os2.process_wait(p)
	if error != nil {
		fmt.printfln("Error: %v", error)
		return "", state
	}
	out := string(output)
	lines := strings.trim(out, "\n")
	return lines, state
}
