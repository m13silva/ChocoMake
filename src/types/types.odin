package types

VariableKind :: enum {
	Normal,
	Reference,
	Selector,
	Template,
}

Selector :: struct {
	source:  string,
	mapping: map[string]string,
	default: string,
}

TemplateEntry :: struct {
	key:    string,
	values: [dynamic]string,
}

Template :: struct {
	pattern: string,
	entries: [dynamic]TemplateEntry,
}

Variable :: struct {
	name:  string,
	kind:  VariableKind,
	value: union {
		string,
		Selector,
		Template,
	},
}

Target :: struct {
	build: [dynamic]string,
	run:   [dynamic]string,
	copy:  [dynamic]string,
	clean: [dynamic]string,
}

Config :: struct {
	default_target: string,
	targets:        map[string]Target,
	variables:      map[string]Variable,
	flags:          []string,
	current_group:  string,
	current_flag:   string,
}

