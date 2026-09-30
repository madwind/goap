@tool
extends HSplitContainer

signal create_requested(kind: String)
signal definition_changed(kind: String, id: String)

const Data = preload("res://addons/goap/visual_editor/goap_editor_data.gd")
var agent: GoapAgent
var filter: LineEdit
var kind_picker: OptionButton
var entries: ItemList
var details: VBoxContainer
var summary: Label
var records: Array[Dictionary] = []
var selected_key := ""
var create_buttons: Array[Button] = []


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 280
	add_child(sidebar)
	filter = LineEdit.new()
	filter.placeholder_text = "Find action, goal, fact or ID..."
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(_text: String) -> void: _populate())
	sidebar.add_child(filter)
	kind_picker = OptionButton.new()
	for kind in ["All definitions", "Actions", "Goals", "Facts"]:
		kind_picker.add_item(kind)
	kind_picker.item_selected.connect(func(_index: int) -> void: _populate())
	sidebar.add_child(kind_picker)
	entries = ItemList.new()
	entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries.item_selected.connect(_select)
	entries.item_activated.connect(_activate)
	sidebar.add_child(entries)
	var buttons := HBoxContainer.new()
	sidebar.add_child(buttons)
	for kind: String in ["Action", "Goal"]:
		var button := Button.new()
		button.text = "+ " + kind
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: create_requested.emit(kind))
		buttons.add_child(button)
		create_buttons.append(button)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	set_agent(null)


func set_agent(value: GoapAgent, additional_facts: Array[StringName] = []) -> void:
	agent = value
	records.clear()
	for button in create_buttons:
		button.disabled = agent == null or agent.goap_script_folder.is_empty()
		button.tooltip_text = "Create a GDScript definition in the Agent's script folder."
	if agent != null:
		for action in agent.actions:
			records.append({ "kind": "Action", "definition": action, "key": "Action:" + action.get_id(), "label": _display_label(String(action.name)) })
		for goal in agent.goals:
			records.append({ "kind": "Goal", "definition": goal, "key": "Goal:" + goal.get_id(), "label": _display_label(String(goal.name)) })
		var facts := Data.fact_keys(agent)
		for fact in additional_facts:
			if not facts.has(fact):
				facts.append(fact)
		facts.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for fact in facts:
			records.append({ "kind": "Fact", "fact": fact, "key": "Fact:" + fact, "label": _display_label(agent.get_world_state_label(fact)) })
	_populate()


func _display_label(raw: String) -> String:
	# Keep the planning key and any variant details intact; format only the title.
	var marker := "*" if raw.begins_with("*") else ""
	var label := raw.trim_prefix("*").strip_edges() if not marker.is_empty() else raw.strip_edges()
	var suffix := ""
	var detail_start := label.find(" (")
	if detail_start >= 0:
		suffix = label.substr(detail_start)
		label = label.substr(0, detail_start)
	var boundary := RegEx.new()
	boundary.compile("([a-z0-9])([A-Z])")
	label = boundary.sub(label, "$1 $2", true)
	boundary.compile("([A-Z])([A-Z][a-z])")
	label = boundary.sub(label, "$1 $2", true)
	label = label.replace("_", " ").to_lower().strip_edges()
	if not label.is_empty():
		label = label[0].to_upper() + label.substr(1)
	return marker + label + suffix


func _populate() -> void:
	entries.clear()
	var selected := -1
	var kinds := ["", "Action", "Goal", "Fact"]
	for record in records:
		if kind_picker.selected > 0 and record.kind != kinds[kind_picker.selected]:
			continue
		if not filter.text.is_empty() and not (record.label + " " + record.key).containsn(filter.text):
			continue
		var index := entries.item_count
		entries.add_item("%s  ·  %s" % [record.kind, record.label])
		entries.set_item_metadata(index, record)
		entries.set_item_tooltip(index, record.key)
		if record.key == selected_key:
			selected = index
	summary.text = "%d definitions / facts" % entries.item_count if agent != null else "Open a scene containing a GoapAgent."
	if entries.item_count > 0:
		selected = maxi(selected, 0)
		entries.select(selected)
		_select(selected)
	else:
		_clear_details()
		_label("No matching definitions." if agent != null else "Select an Agent to browse its definitions.")


func select_definition(kind: String, id: String) -> void:
	selected_key = kind + ":" + id
	filter.clear()
	kind_picker.select(0)
	_populate()
	entries.ensure_current_is_visible()


func _select(index: int) -> void:
	var record: Dictionary = entries.get_item_metadata(index)
	selected_key = record.key
	_clear_details()
	if record.kind == "Fact":
		_label(record.label, 22)
		_label("Fact · Preview: %s" % _value_text(agent.world_state.get_state(record.fact)))
		var sources := agent.get_world_state_sources(record.fact)
		if not sources.is_empty():
			_label("Source", 16)
			for source in sources:
				var open_source := Button.new()
				open_source.text = source.label
				open_source.alignment = HORIZONTAL_ALIGNMENT_LEFT
				open_source.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				open_source.tooltip_text = source.path + (" :: " + source.method if source.has("method") else "")
				open_source.pressed.connect(func() -> void: _open_source(source))
				details.add_child(open_source)
		var references := Data.references(agent, record.fact)
		_label("References", 16)
		if references.is_empty():
			_label("No action or goal references this fact yet.")
		for reference in references:
			var definition: RefCounted = reference.definition
			var button := Button.new()
			button.text = "%s %s  ·  %s [%s]" % [reference.role, str(reference.value), _display_label(String(definition.name)), definition.get_id()]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.tooltip_text = button.text
			button.pressed.connect(func() -> void: select_definition(reference.kind, definition.get_id()))
			details.add_child(button)
		return
	var definition: RefCounted = record.definition
	var script := GoapTheme.definition_script(definition)
	var heading := _heading_row(record.label, 22)
	if script != null:
		var open := Button.new()
		open.text = "Open %s script" % record.kind.to_lower()
		open.pressed.connect(func() -> void: _open_script(script))
		heading.add_child(open)
	_label("%s · ID: %s" % [record.kind, definition.get_id()])
	_label("Defined by GDScript. Simple states below save directly to the source; edit other logic in the script.")
	if script != null:
		_label(script.resource_path)
	if definition is GoapAction:
		_editable_action_state("Preconditions", definition, "_get_preconditions", definition.preconditions)
		_editable_action_state("Effects", definition, "_get_effects", definition.effects)
		var model: GDScript = definition.get_cost_model() if definition.has_method("get_cost_model") else GoapCostModel
		if model == GoapCostModel:
			_editable_action_cost(definition)
		elif model != null:
			_model_actions(definition, model, script)
		else:
			_label("Cost model is missing.", 16)
		_label("Runtime shows evaluated costs and action availability. Preview shows structural sequences.")
	else:
		_facts("Desired state", definition.goal_state)
		_label("Priority chooses goals at runtime. Structural preview does not rank goals by Priority.")


func _model_actions(action: GoapAction, model: GDScript, script: Script) -> void:
	_label("Cost model", 16)
	_label(model.resource_path)
	var row := HBoxContainer.new()
	details.add_child(row)
	var open := Button.new()
	open.text = "Open cost script"
	open.pressed.connect(func() -> void: _open_script(model))
	row.add_child(open)
	var detach := Button.new()
	detach.text = "Detach"
	detach.tooltip_text = "Use this action's default cost instead; keep the shared model script."
	row.add_child(detach)
	if script == null:
		detach.disabled = true
		return
	var source := FileAccess.get_file_as_string(script.resource_path)
	if FileAccess.get_open_error() != OK or script.source_code != source:
		detach.disabled = true
		_label("Save the action script before detaching its model.")
		return
	detach.pressed.connect(func() -> void:
		_apply_cost_model_change(action, script, source))


func _editable_action_cost(action: GoapAction) -> void:
	_label("Action cost", 16)
	var script := GoapTheme.definition_script(action)
	var editable: Dictionary = Data.action_cost_source(script, action.cost)
	if editable.has("error"):
		_label("%s · %s" % [str(action.cost), editable.error])
		if script != null:
			var current_source := FileAccess.get_file_as_string(script.resource_path)
			if FileAccess.get_open_error() == OK and script.source_code == current_source:
				_cost_model_buttons(action, script, current_source)
		return
	var source: String = editable.source
	var row := HBoxContainer.new()
	details.add_child(row)
	var input := SpinBox.new()
	input.name = "ActionCostInput"
	input.min_value = 0.0
	input.max_value = 1000000000000.0
	input.step = 0.1
	input.value = action.cost
	input.custom_minimum_size.x = 130
	row.add_child(input)
	var save := Button.new()
	save.text = "Save cost"
	save.pressed.connect(func() -> void:
		var open_editor := _open_action_editor(script)
		if open_editor != null and open_editor.text != source:
			_edit_error("Save the open script before editing its cost here.")
			return
		var result: Dictionary = Data.write_action_cost(script, source, input.value)
		if result.has("error"):
			_edit_error(result.error)
			_populate()
			return
		EditorInterface.get_resource_filesystem().scan()
		if open_editor != null:
			open_editor.text = result.source
			open_editor.tag_saved_version()
		definition_changed.emit("Action", action.get_id()))
	row.add_child(save)
	_cost_model_buttons(action, script, source)


func _cost_model_buttons(action: GoapAction, script: Script, source: String) -> void:
	var model_buttons := HBoxContainer.new()
	details.add_child(model_buttons)
	var add := Button.new()
	add.text = "Add new cost model"
	add.disabled = agent == null or agent.goap_script_folder.is_empty()
	add.tooltip_text = "Create a cost model in the Agent's costs folder and attach it to this action."
	add.pressed.connect(func() -> void: _add_cost_model(action, script, source))
	model_buttons.add_child(add)
	var attach := Button.new()
	attach.text = "Attach existing cost model..."
	attach.pressed.connect(func() -> void: _choose_cost_model(action, script, source))
	model_buttons.add_child(attach)


func _choose_cost_model(action: GoapAction, script: Script, source: String) -> void:
	var picker := FileDialog.new()
	picker.title = "Attach cost model"
	picker.access = FileDialog.ACCESS_RESOURCES
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.gd ; GDScript"])
	add_child(picker)
	picker.file_selected.connect(func(path: String) -> void:
		_apply_cost_model_change(action, script, source, path)
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.6)


func _add_cost_model(action: GoapAction, script: Script, source: String) -> void:
	if script == null or agent == null:
		return
	var filename := script.resource_path.get_file().get_basename() + "_cost"
	var result: Dictionary = Data.create_cost_model(agent.goap_script_folder, filename)
	if result.has("error"):
		_edit_error(result.error)
		return
	if not _apply_cost_model_change(action, script, source, result.path):
		DirAccess.remove_absolute(result.path)
		return
	EditorInterface.get_resource_filesystem().update_file(result.path)
	_open_script(load(result.path))


func _apply_cost_model_change(action: GoapAction, script: Script, source: String, model_path := "") -> bool:
	var open_editor := _open_action_editor(script)
	if open_editor != null and open_editor.text != source:
		_edit_error("Save the open action script before changing its cost model.")
		return false
	var result: Dictionary = Data.detach_cost_model(script, source) if model_path.is_empty() else Data.attach_cost_model(script, source, model_path)
	if result.has("error"):
		_edit_error(result.error)
		_populate()
		return false
	EditorInterface.get_resource_filesystem().scan()
	if open_editor != null:
		open_editor.text = result.source
		open_editor.tag_saved_version()
	definition_changed.emit("Action", action.get_id())
	return true


func _editable_action_state(title: String, action: GoapAction, method: String, state: GoapWorldState) -> void:
	var heading := _heading_row(title, 16)
	var script := GoapTheme.definition_script(action)
	var editable: Dictionary = Data.action_state_source(script, method, state)
	if editable.has("error"):
		_facts_without_heading(state)
		_label(editable.error)
		return
	var source: String = editable.source
	var state_entries: Array = editable.entries
	_facts_without_heading(state)
	var available: Array[Dictionary] = []
	for record in records:
		if record.kind != "Fact":
			continue
		var fact: StringName = record.fact
		available.append({ "fact": fact, "label": record.label })
	var edit := Button.new()
	edit.text = "Edit..."
	edit.disabled = available.is_empty()
	edit.tooltip_text = "Edit this action's world state facts" if not available.is_empty() else "No world state facts available"
	edit.pressed.connect(func() -> void:
		_show_edit_fact_dialog(title, available, script, method, source, state_entries, action.get_id()))
	heading.add_child(edit)


func _show_edit_fact_dialog(title: String, available: Array[Dictionary], script: Script, method: String, source: String, state_entries: Array, id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Edit %s" % title
	dialog.ok_button_text = "Save states"
	dialog.min_size = Vector2i(660, 440)
	add_child(dialog)
	var form := VBoxContainer.new()
	dialog.add_child(form)
	var filters := HBoxContainer.new()
	form.add_child(filters)
	var search := LineEdit.new()
	search.name = "FactSearch"
	search.placeholder_text = "Search world state facts..."
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	var selected_only := CheckBox.new()
	selected_only.name = "IncludedOnly"
	selected_only.text = "Included only"
	filters.add_child(selected_only)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 280
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(scroll)
	var table := GridContainer.new()
	table.name = "FactTable"
	table.columns = 3
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 16)
	scroll.add_child(table)
	var selected := {}
	var values := {}
	for entry in state_entries:
		var fact: StringName = entry.fact
		selected[fact] = true
		values[fact] = entry.value
	search.text_changed.connect(func(query: String) -> void:
		_populate_fact_dialog(table, available, selected, values, query, selected_only.button_pressed))
	selected_only.toggled.connect(func(enabled: bool) -> void:
		_populate_fact_dialog(table, available, selected, values, search.text, enabled))
	_populate_fact_dialog(table, available, selected, values, "", false)
	dialog.confirmed.connect(func() -> void:
		dialog.hide()
		var changed := []
		var existing := {}
		for entry in state_entries:
			var fact: StringName = entry.fact
			existing[fact] = true
			if selected.has(fact):
				var updated: Dictionary = entry.duplicate(true)
				updated["value"] = values.get(fact, entry.value)
				changed.append(updated)
		for option in available:
			var fact: StringName = option.fact
			if selected.has(fact) and not existing.has(fact):
				changed.append({ "expression": Data.fact_expression(script, fact, agent.fact_key_script), "value": values.get(fact, false) })
		_save_action_entries(script, method, source, changed, id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	search.grab_focus()


func _populate_fact_dialog(table: GridContainer, available: Array[Dictionary], selected: Dictionary, values: Dictionary, query: String, selected_only: bool) -> void:
	for child in table.get_children():
		child.free()
	for title in ["World state fact", "Include", "True / False"]:
		var header := Label.new()
		header.text = title
		table.add_child(header)
	var count := 0
	for option in available:
		var fact: StringName = option.fact
		var label: String = option.label
		if not query.is_empty() and not (label + " " + String(fact)).containsn(query):
			continue
		if selected_only and not selected.has(fact):
			continue
		count += 1
		var fact_label := Label.new()
		fact_label.text = label if label == String(fact) else "%s  (%s)" % [label, fact]
		fact_label.tooltip_text = String(fact)
		fact_label.custom_minimum_size.x = 350
		fact_label.clip_text = true
		table.add_child(fact_label)
		var select_check := CheckBox.new()
		select_check.name = "IncludeFact"
		select_check.set_meta("fact", fact)
		select_check.set_meta("role", "include")
		select_check.set_pressed_no_signal(selected.has(fact))
		var value_check := CheckBox.new()
		value_check.name = "FactValue"
		value_check.set_meta("fact", fact)
		value_check.set_meta("role", "value")
		value_check.tooltip_text = "Checked = true; unchecked = false"
		value_check.set_pressed_no_signal(values.get(fact, false))
		value_check.disabled = not selected.has(fact)
		select_check.toggled.connect(func(enabled: bool) -> void:
			if enabled:
				selected[fact] = true
			else:
				selected.erase(fact)
			value_check.disabled = not enabled
			if selected_only and not enabled:
				_populate_fact_dialog.call_deferred(table, available, selected, values, query, true))
		table.add_child(select_check)
		value_check.toggled.connect(func(enabled: bool) -> void: values[fact] = enabled)
		table.add_child(value_check)
	if count == 0:
		var empty := Label.new()
		empty.text = "No matching facts."
		table.add_child(empty)


func _save_action_entries(script: Script, method: String, source: String, state_entries: Array, id: String) -> void:
	var open_editor := _open_action_editor(script)
	if open_editor != null and open_editor.text != source:
		_edit_error("Save the open script before editing its states here.")
		return
	var result: Dictionary = Data.write_action_state(script, method, source, state_entries)
	if result.has("error"):
		_edit_error(result.error)
		_populate()
		return
	EditorInterface.get_resource_filesystem().scan()
	if open_editor != null:
		open_editor.text = result.source
		open_editor.tag_saved_version()
	definition_changed.emit("Action", id)


func _open_action_editor(script: Script) -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor()
	var scripts := script_editor.get_open_scripts()
	var editors := script_editor.get_open_script_editors()
	for index in mini(scripts.size(), editors.size()):
		if scripts[index] != null and scripts[index].resource_path == script.resource_path:
			return editors[index].get_base_editor() as CodeEdit
	return null


func _edit_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Cannot edit action"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _facts(title: String, state: GoapWorldState) -> void:
	_label(title, 16)
	_facts_without_heading(state)


func _facts_without_heading(state: GoapWorldState) -> void:
	if state.size() == 0:
		_label("None")
	var facts := state.keys()
	facts.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for fact in facts:
		var button := Button.new()
		button.text = "%s = %s    → References" % [_display_label(agent.get_world_state_label(fact)), str(state.get_state(fact))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = "%s = %s" % [fact, str(state.get_state(fact))]
		button.pressed.connect(func() -> void: select_definition("Fact", fact))
		details.add_child(button)


func _activate(index: int) -> void:
	var record: Dictionary = entries.get_item_metadata(index)
	if record.has("definition"):
		_open_script(GoapTheme.definition_script(record.definition))


func _open_source(source: Dictionary) -> void:
	var resource := load(String(source.path))
	if resource is Script:
		var line := -1
		if source.has("method"):
			var lines: PackedStringArray = resource.source_code.split("\n")
			for index in lines.size():
				if lines[index].begins_with("func " + source.method + "(") or lines[index].begins_with("static func " + source.method + "("):
					line = index
					break
		EditorInterface.edit_script(resource, line)
		EditorInterface.set_main_screen_editor("Script")
	elif resource is PackedScene:
		EditorInterface.open_scene_from_path(source.path)
	elif resource != null:
		EditorInterface.edit_resource(resource)


func _open_script(script: Script) -> void:
	if script != null:
		EditorInterface.edit_script(script)
		EditorInterface.set_main_screen_editor("Script")


func _clear_details() -> void:
	for child in details.get_children():
		child.queue_free()
		details.remove_child(child)


func _label(text: String, font_size: int = 0) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	details.add_child(label)


func _value_text(value: Variant) -> String:
	return str(value)


func _heading_row(title: String, font_size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	details.add_child(row)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", font_size)
	row.add_child(label)
	return row
