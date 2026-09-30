@tool
extends RefCounted

## Only a literal _get_cost() return, or the inherited default, is editable.
static func action_cost_source(script: Script, cost: float) -> Dictionary:
	if script == null:
		return { "error": "This action has no editable script." }
	var source := FileAccess.get_file_as_string(script.resource_path)
	if FileAccess.get_open_error() != OK:
		return { "error": "Cannot read the action script." }
	if script.source_code != source:
		return { "error": "Save the open script before editing its cost here." }
	var parsed := _literal_cost_method(source)
	if parsed.has("error"):
		return parsed
	if not is_equal_approx(parsed.value, cost):
		return { "error": "This cost is changed by code. Edit it in GDScript." }
	return { "source": source }


static func write_action_cost(script: Script, expected_source: String, cost: float) -> Dictionary:
	if script == null or not is_finite(cost) or cost < 0.0:
		return { "error": "Cost must be a finite, non-negative number." }
	var path := script.resource_path
	var source := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK or source != expected_source or script.source_code != source:
		return { "error": "The script changed since this panel opened. Save it and Reload first." }
	var parsed := _literal_cost_method(source)
	if parsed.has("error"):
		return parsed
	var newline := "\r\n" if source.contains("\r\n") else "\n"
	var updated: String
	if parsed.line == -1:
		updated = source.strip_edges(false, true) + newline + newline + "func _get_cost() -> float:" + newline + "\treturn " + str(cost) + newline
	else:
		var lines := source.split("\n")
		lines[parsed.line] = "\treturn " + str(cost) + ("\r" if lines[parsed.line].ends_with("\r") else "")
		updated = "\n".join(lines)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { "error": "Cannot write the action script." }
	file.store_string(updated)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return { "error": "Failed to save the action script." }
	script.source_code = updated
	var reload_error := script.reload(true)
	if reload_error != OK:
		return { "error": "The file was saved, but Godot could not reload it. Open the script to inspect the error." }
	return { "source": updated }


static func _literal_cost_method(source: String) -> Dictionary:
	var lines := source.split("\n")
	var declaration := "func _get_cost() -> float:"
	var found := -1
	for index in lines.size():
		if lines[index].trim_suffix("\r") == declaration:
			if found != -1:
				return { "error": "Duplicate cost method. Edit it in GDScript." }
			found = index
	if found == -1:
		return { "line": -1, "value": 1.0 }
	var body_line := -1
	for index in range(found + 1, lines.size()):
		var line := lines[index].trim_suffix("\r")
		if line.strip_edges().is_empty():
			continue
		if not line.begins_with("\t"):
			break
		if body_line != -1:
			return { "error": "This cost is computed. Edit it in GDScript." }
		body_line = index
	if body_line == -1:
		return { "error": "The cost method has no editable return." }
	var body := lines[body_line].trim_suffix("\r").strip_edges()
	if not body.begins_with("return "):
		return { "error": "Only a literal cost return is editable here." }
	var number := body.trim_prefix("return ")
	if not number.is_valid_float() or not is_finite(float(number)):
		return { "error": "Only a finite numeric cost is editable here." }
	return { "line": body_line, "value": float(number) }


## Detach only this action. A shared cost model script is never removed.
static func detach_cost_model(script: Script, expected_source: String) -> Dictionary:
	return _write_cost_model_reference(script, expected_source, "GoapCostModel")


static func attach_cost_model(script: Script, expected_source: String, model_path: String) -> Dictionary:
	if not model_path.begins_with("res://") or model_path.contains("..") or not model_path.ends_with(".gd"):
		return { "error": "Choose a GDScript cost model inside this project." }
	var model := load(model_path) as GDScript
	if model == null or model == GoapCostModel:
		return { "error": "Choose a script extending GoapCostModel." }
	var issues := GoapPlanningSafety.inspect_model(model)
	if not issues.is_empty():
		return { "error": issues[0] }
	return _write_cost_model_reference(script, expected_source, "preload(%s)" % JSON.stringify(model_path))


static func create_cost_model(folder: String, filename: String) -> Dictionary:
	if not folder.begins_with("res://") or folder.contains(".."):
		return { "error": "Choose a project script folder." }
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*$")
	if pattern.search(filename) == null:
		return { "error": "Use a snake_case model file name without .gd." }
	var path := folder.path_join("costs").path_join(filename + ".gd")
	if FileAccess.file_exists(path):
		return { "error": "That cost model script already exists." }
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return { "error": "Cannot create the cost model directory: %s" % error_string(error) }
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { "error": "Cannot create the cost model script." }
	file.store_string("extends GoapCostModel\n\n\nstatic func get_cost(_simulation: Dictionary, _context: Dictionary) -> float:\n\treturn 1.0\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return { "error": "Failed to save the cost model script." }
	return { "path": path }


static func _write_cost_model_reference(script: Script, expected_source: String, expression: String) -> Dictionary:
	if script == null:
		return { "error": "This action has no editable script." }
	var path := script.resource_path
	var source := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK or source != expected_source or script.source_code != source:
		return { "error": "The script changed since this panel opened. Save it and Reload first." }
	var parsed := _cost_model_method(source)
	if parsed.has("error"):
		return parsed
	var newline := "\r\n" if source.contains("\r\n") else "\n"
	var updated: String
	if parsed.line == -1:
		updated = source.strip_edges(false, true) + newline + newline + "func get_cost_model() -> GDScript:" + newline + "\treturn " + expression + newline
	else:
		var lines := source.split("\n")
		lines[parsed.line] = "\treturn " + expression + ("\r" if lines[parsed.line].ends_with("\r") else "")
		updated = "\n".join(lines)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { "error": "Cannot write the action script." }
	file.store_string(updated)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return { "error": "Failed to save the action script." }
	script.source_code = updated
	var reload_error := script.reload(true)
	if reload_error != OK:
		return { "error": "The file was saved, but Godot could not reload it. Open the script to inspect the error." }
	return { "source": updated }


static func _cost_model_method(source: String) -> Dictionary:
	var lines := source.split("\n")
	var declaration := "func get_cost_model() -> GDScript:"
	var found := -1
	for index in lines.size():
		if lines[index].trim_suffix("\r") == declaration:
			if found != -1:
				return { "error": "Duplicate cost model method. Edit it in GDScript." }
			found = index
	if found == -1:
		return { "line": -1 }
	var body_line := -1
	for index in range(found + 1, lines.size()):
		var line := lines[index].trim_suffix("\r")
		if line.strip_edges().is_empty():
			continue
		if not line.begins_with("\t"):
			break
		if body_line != -1:
			return { "error": "This model selection is computed. Edit it in GDScript." }
		body_line = index
	if body_line == -1 or not lines[body_line].trim_suffix("\r").strip_edges().begins_with("return "):
		return { "error": "This model selection needs manual GDScript editing." }
	return { "line": body_line }


## Only a single literal return is editable. Other GDScript stays under manual control.
static func action_state_source(script: Script, method: String, state: GoapWorldState) -> Dictionary:
	if script == null or method not in ["_get_preconditions", "_get_effects"]:
		return { "error": "This action has no editable script." }
	var source := FileAccess.get_file_as_string(script.resource_path)
	if FileAccess.get_open_error() != OK:
		return { "error": "Cannot read the action script." }
	if script.source_code != source:
		return { "error": "Save the open script before editing its states here." }
	var parsed := _literal_state_method(source, method)
	if parsed.has("error"):
		return parsed
	var entries: Array = parsed.entries
	if entries.size() != state.size():
		return { "error": "This state is changed by code after construction. Edit it in GDScript." }
	var seen := {}
	for entry in entries:
		var fact := _resolve_fact(script, entry.expression)
		if fact == null or seen.has(fact) or not state.has_state(fact) or entry.value != state.get_state(fact):
			return { "error": "This state is changed by code after construction. Edit it in GDScript." }
		seen[fact] = true
		entry["fact"] = fact
	return { "source": source, "entries": entries }


static func write_action_state(script: Script, method: String, expected_source: String, entries: Array) -> Dictionary:
	if script == null or method not in ["_get_preconditions", "_get_effects"]:
		return { "error": "Invalid action state method." }
	var path := script.resource_path
	var source := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK or source != expected_source or script.source_code != source:
		return { "error": "The script changed since this panel opened. Save it and Reload first." }
	var parsed := _literal_state_method(source, method)
	if parsed.has("error"):
		return parsed
	var parts := PackedStringArray()
	for entry in entries:
		if not entry is Dictionary or not entry.has("expression") or not entry.has("value") or not entry.value is bool:
			return { "error": "Invalid state entry." }
		var expression: String = entry.expression
		if not _valid_fact_expression(expression):
			return { "error": "Invalid fact key. Use a literal fact name or an existing constant." }
		parts.append("%s: %s" % [expression, str(entry.value)])
	var body := "\treturn GoapWorldState.new({ %s })" % ", ".join(parts) if not parts.is_empty() else "\treturn GoapWorldState.new()"
	var lines := source.split("\n")
	lines[parsed.line] = body + ("\r" if lines[parsed.line].ends_with("\r") else "")
	var updated := "\n".join(lines)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { "error": "Cannot write the action script." }
	file.store_string(updated)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return { "error": "Failed to save the action script." }
	script.source_code = updated
	var reload_error := script.reload(true)
	if reload_error != OK:
		return { "error": "The file was saved, but Godot could not reload it. Open the script to inspect the error." }
	return { "source": updated }


static func _literal_state_method(source: String, method: String) -> Dictionary:
	var lines := source.split("\n")
	var declaration := "func %s() -> GoapWorldState:" % method
	var found := -1
	for index in lines.size():
		if lines[index].trim_suffix("\r") == declaration:
			if found != -1:
				return { "error": "Duplicate state method. Edit it in GDScript." }
			found = index
	if found == -1:
		return { "error": "This state is inherited or computed. Edit it in GDScript." }
	var body_line := -1
	for index in range(found + 1, lines.size()):
		var line := lines[index].trim_suffix("\r")
		if line.strip_edges().is_empty():
			continue
		if not line.begins_with("\t"):
			break
		if body_line != -1:
			return { "error": "This method contains code beyond a literal return. Edit it in GDScript." }
		body_line = index
	if body_line == -1:
		return { "error": "The state method has no editable return." }
	var body := lines[body_line].trim_suffix("\r").strip_edges()
	if body == "return GoapWorldState.new()" or body == "return GoapWorldState.new({})":
		return { "line": body_line, "entries": [] }
	if not body.begins_with("return GoapWorldState.new({") or not body.ends_with("})"):
		return { "error": "Only a literal GoapWorldState.new({ ... }) return is editable here." }
	var content := body.substr("return GoapWorldState.new({".length(), body.length() - "return GoapWorldState.new({".length() - 2).strip_edges()
	var entries := []
	if not content.is_empty():
		for item in _split_outside_strings(content, ","):
			var pair := _split_outside_strings(item.strip_edges(), ":")
			if pair.size() != 2:
				return { "error": "This dictionary needs manual GDScript editing." }
			var expression := pair[0].strip_edges()
			var value := pair[1].strip_edges()
			if not _valid_fact_expression(expression) or value not in ["true", "false"]:
				return { "error": "This dictionary needs manual GDScript editing." }
			entries.append({ "expression": expression, "value": value == "true" })
	return { "line": body_line, "entries": entries }


static func _valid_fact_expression(expression: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile('^(?:&?"(?:\\\\.|[^"\\\\\\r\\n])*"|[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*|preload\\("(?:\\\\.|[^"\\\\\\r\\n])*"\\)\\.[A-Za-z_][A-Za-z0-9_]*)$')
	return pattern.search(expression) != null


static func _split_outside_strings(source: String, separator: String) -> PackedStringArray:
	var result := PackedStringArray()
	var quoted := false
	var escaped := false
	var start := 0
	for index in source.length():
		var character := source[index]
		if quoted and escaped:
			escaped = false
		elif quoted and character == "\\":
			escaped = true
		elif character == '"':
			quoted = not quoted
		elif not quoted and character == separator:
			result.append(source.substr(start, index - start))
			start = index + 1
	result.append(source.substr(start))
	return result


static func _resolve_fact(script: Script, expression: String) -> Variant:
	if expression.begins_with('"') or expression.begins_with('&"'):
		return StringName(JSON.parse_string(expression.trim_prefix("&")))
	if expression.begins_with("preload("):
		var close := expression.find(").")
		if close == -1:
			return null
		var path := JSON.parse_string(expression.substr("preload(".length(), close - "preload(".length()))
		if not path is String:
			return null
		var owner := load(path) as Script
		if owner == null:
			return null
		var constant_name := expression.substr(close + 2)
		var values: Dictionary = owner.get_script_constant_map()
		if not values.has(constant_name) or not values[constant_name] is StringName:
			return null
		return values[constant_name]
	var names := expression.split(".")
	var constants := script.get_script_constant_map()
	if names.size() != 2 or not constants.has(names[0]):
		return null
	var owner: Variant = constants[names[0]]
	if not owner is Script:
		return null
	var values: Dictionary = owner.get_script_constant_map()
	if not values.has(names[1]) or not values[names[1]] is StringName:
		return null
	return values[names[1]]


static func fact_expression(script: Script, fact: StringName, vocabulary: Script = null) -> String:
	var constants := script.get_script_constant_map()
	var aliases := constants.keys()
	aliases.sort()
	for alias in aliases:
		var owner: Variant = constants[alias]
		if not owner is Script:
			continue
		var values: Dictionary = owner.get_script_constant_map()
		var names := values.keys()
		names.sort()
		for name in names:
			if values[name] is StringName and values[name] == fact:
				return "%s.%s" % [alias, name]
	if vocabulary != null and not vocabulary.resource_path.is_empty():
		var values: Dictionary = vocabulary.get_script_constant_map()
		var names := values.keys()
		names.sort()
		for name in names:
			if values[name] is StringName and values[name] == fact:
				return 'preload(%s).%s' % [JSON.stringify(vocabulary.resource_path), name]
	return "&" + JSON.stringify(String(fact))

static func fact_keys(agent: GoapAgent) -> Array[StringName]:
	var keys: Dictionary = {}
	for key in agent.world_state.keys():
		keys[key] = true
	for action in agent.actions:
		for key in action.preconditions.keys() + action.effects.keys():
			keys[key] = true
	for goal in agent.goals:
		for key in goal.goal_state.keys():
			keys[key] = true
	var result: Array[StringName] = []
	result.assign(keys.keys())
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result


static func references(agent: GoapAgent, fact: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in agent.actions:
		if action.preconditions.has_state(fact):
			result.append({ "kind": "Action", "definition": action, "role": "Requires", "value": action.preconditions.get_state(fact) })
		if action.effects.has_state(fact):
			result.append({ "kind": "Action", "definition": action, "role": "Writes", "value": action.effects.get_state(fact) })
	for goal in agent.goals:
		if goal.goal_state.has_state(fact):
			result.append({ "kind": "Goal", "definition": goal, "role": "Desires", "value": goal.goal_state.get_state(fact) })
	return result


static func template_path(folder: String, kind: String, filename: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^[a-z][a-z0-9_]*$")
	if kind not in ["Action", "Goal"] or pattern.search(filename) == null:
		return ""
	if not folder.begins_with("res://") or folder.contains(".."):
		return ""
	return folder.path_join("actions" if kind == "Action" else "goals").path_join(filename + ".gd")


static func template_id(filename: String) -> String:
	return filename.to_pascal_case()


static func create_template(
	folder: String,
	kind: String,
	filename: String,
	fact := "",
	value := true
) -> Dictionary:
	var path := template_path(folder, kind, filename)
	if path.is_empty():
		return { "error": "Use a snake_case file name and a project folder." }
	if FileAccess.file_exists(path):
		return { "error": "That script already exists. Choose a different file name." }
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return { "error": "Cannot create the definition directory: %s" % error_string(error) }
	var identifier := JSON.stringify(template_id(filename))
	var fact_literal := JSON.stringify(fact.strip_edges())
	var state := "GoapWorldState.new()" if fact.strip_edges().is_empty() else "GoapWorldState.new({ &%s: %s })" % [fact_literal, str(value)]
	var source: String
	if kind == "Action":
		source = "extends GoapAction\n\n\nfunc _get_name() -> StringName:\n\treturn &%s\n\n\nfunc _get_preconditions() -> GoapWorldState:\n\treturn GoapWorldState.new()\n\n\nfunc _get_effects() -> GoapWorldState:\n\treturn %s\n\n\nfunc _get_cost() -> float:\n\treturn 1.0\n\n\n# Enable after implementing the actor's behavior. Structural preview still includes it.\nfunc is_valid(_agent: GoapAgent) -> bool:\n\treturn false\n\n\nfunc start(_agent: GoapAgent) -> void:\n\tpass\n\n\nfunc perform(_agent: GoapAgent, _delta: float) -> Status:\n\treturn Status.FAILURE\n\n\nfunc stop(_agent: GoapAgent) -> void:\n\tpass\n" % [identifier, state]
	else:
		source = "extends GoapGoal\n\n\nfunc _get_name() -> String:\n\treturn %s\n\n\nfunc _get_goal_state() -> GoapWorldState:\n\treturn %s\n\n\n# Set the priority rule before enabling this goal at runtime.\nfunc get_priority(_state: GoapWorldState) -> float:\n\treturn 0.0\n" % [identifier, state]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return { "error": "Cannot write script: %s" % error_string(FileAccess.get_open_error()) }
	file.store_string(source)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return { "error": "Cannot finish writing script: %s" % error_string(write_error) }
	return { "path": path }
