class_name GoapPlanningSafety
extends RefCounted
## Best-effort source diagnostics, not a GDScript sandbox. Run on the main thread.
static var _reported: Dictionary = {}
static var _audited: Dictionary = {}
static var _autoload_names: Array[String] = []
static var _autoloads_loaded := false


static func warn(message: String) -> void:
	if not _reported.has(message):
		_reported[message] = true
		push_warning("GOAP planning: " + message)


static func impure_path(value: Variant, path := "snapshot") -> String:
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return "%s contains %s; copy values in capture_context() instead of scene references" % [
				path,
				type_string(typeof(value))
			]
		TYPE_ARRAY:
			for index in value.size():
				var problem := impure_path(value[index], "%s[%d]" % [path, index])
				if not problem.is_empty():
					return problem
		TYPE_DICTIONARY:
			for key: Variant in value:
				var problem := impure_path(key, path + ".<key>")
				if problem.is_empty():
					problem = impure_path(value[key], "%s[%s]" % [path, str(key)])
				if not problem.is_empty():
					return problem
	return ""


static func capture(action: GoapAction, agent: GoapAgent, supplied: Variant = null) -> Dictionary:
	var id := action.get_id()
	var model: GDScript = action.get_cost_model() if action.has_method("get_cost_model") else GoapCostModel
	var issues := inspect_model(model)
	if not issues.is_empty():
		for issue in issues:
			warn("%s: %s" % [id, issue])
		return { "error": "%s: %s" % [id, issues[0]] }
	var context: Variant = supplied
	if context == null:
		context = action.capture_context(agent) if action.has_method("capture_context") else {}
	var issue := impure_path(context, "%s.capture_context" % id)
	if not context is Dictionary:
		issue = "%s.capture_context must return a Dictionary" % id
	if not issue.is_empty():
		warn(issue)
		return { "error": issue }
	var copied: Dictionary = context.duplicate(true)
	freeze(copied)
	return { "model": model, "context": copied, "cost": action.cost }


static func freeze(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for item: Variant in value:
			freeze(item)
		value.make_read_only()


static func inspect_model(model: GDScript) -> Array[String]:
	var issues: Array[String] = []
	if model == GoapCostModel:
		return issues
	if model == null:
		issues.append("get_cost_model() returned null")
		return issues
	var chain: Array[Script] = []
	var current: Script = model
	while current != null and current != GoapCostModel:
		chain.append(current)
		current = current.get_base_script()
	if current == null:
		issues.append("%s must extend GoapCostModel" % model.resource_path)
		return issues
	var checked: Dictionary = {}
	for method in model.get_script_method_list():
		var name: StringName = method.name
		if name in [&"get_cost", &"apply_cost_effect"] and not checked.has(name):
			checked[name] = true
			if not (int(method.flags) & METHOD_FLAG_STATIC) or method.args.size() != 2:
				issues.append(
					"%s: %s must be static and accept (simulation, context)" % [
						model.resource_path,
						name
					]
				)
	if not _autoloads_loaded:
		for property in ProjectSettings.get_property_list():
			var name: String = property.name
			if name.begins_with("autoload/"):
				_autoload_names.append(name.trim_prefix("autoload/"))
		_autoloads_loaded = true
	for script in chain:
		var source := script.source_code
		var cache_key := str(script.get_instance_id()) + ":" + str(source.hash())
		if not _audited.has(cache_key):
			_audited[cache_key] = inspect_source(source, script.resource_path, _autoload_names)
		issues.append_array(_audited[cache_key])
	return issues


## Call if editor tooling changes the project's autoload list in this process.
static func clear_audit_cache() -> void:
	_audited.clear()
	_autoload_names.clear()
	_autoloads_loaded = false


## Public for editor tooling/tests. Dedicated cost-model source only; runtime
## Action.start/perform/stop/capture_context are deliberately not inspected.
static func inspect_source(
	source: String,
	path: String,
	autoloads: Array[String] = []
) -> Array[String]:
	var issues: Array[String] = []
	if source.is_empty():
		issues.append("%s: no source available to check cost-model scene access" % path)
		return issues
	var code := _strip_strings_and_comments(source)
	var forbidden := RegEx.new()
	forbidden.compile(
		"(?m)\\b(get_tree|get_node|get_node_or_null|get_parent|get_children|find_child|find_children|get_viewport|get_world_2d|get_world_3d|instance_from_id|get_main_loop|get_singleton|SceneTree|Node|Node2D|Node3D|Input|EditorInterface|RenderingServer|PhysicsServer2D|PhysicsServer3D|NavigationServer2D|NavigationServer3D)\\b|\\.global_(position|transform)\\b|\\$|(?:^|[=(,:])\\s*%[A-Za-z_]|\\breturn\\s+%[A-Za-z_]"
	)
	for found in forbidden.search_all(code):
		var line := code.left(found.get_start()).count("\n") + 1
		issues.append(
			"%s:%d: scene/global access '%s' in cost model; read it in capture_context() on the main thread" % [
				path,
				line,
				found.get_string()
			]
		)
	for name in autoloads:
		var pattern := RegEx.new()
		pattern.compile("\\b" + name + "\\b")
		for found in pattern.search_all(code):
			issues.append(
				"%s:%d: autoload '%s' is live shared state; capture its values on the main thread" % [
					path,
					code.left(found.get_start()).count("\n") + 1,
					name
				]
			)
	var shared := RegEx.new()
	shared.compile(
		"(?m)^static\\s+var\\b|(?m)^var\\b|\\b(load|preload|call|callv|Callable|Expression)\\s*\\("
	)
	for found in shared.search_all(code):
		issues.append(
			"%s:%d: mutable state or dynamic code '%s' cannot be checked for worker scene access; keep cost models self-contained" % [
				path,
				code.left(found.get_start()).count("\n") + 1,
				found.get_string()
			]
		)
	return issues


static func _strip_strings_and_comments(source: String) -> String:
	var result := ""
	var quote := ""
	var index := 0
	while index < source.length():
		var character := source[index]
		if not quote.is_empty():
			if character == "\\":
				result += "  "
				index += 2
				continue
			if source.substr(index, quote.length()) == quote:
				result += " ".repeat(quote.length())
				index += quote.length()
				quote = ""
				continue
			result += "\n" if character == "\n" else " "
		elif character == "#":
			while index < source.length() and source[index] != "\n":
				result += " "
				index += 1
			continue
		elif character == "\"" or character == "'":
			quote = character.repeat(3) if source.substr(index, 3) == character.repeat(
				3
			) else character
			result += " ".repeat(quote.length())
			index += quote.length()
			continue
		else:
			result += character
		index += 1
	return result
