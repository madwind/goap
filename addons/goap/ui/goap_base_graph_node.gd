class_name GoapBaseGraphNode
extends GraphNode

var goap_script: Script
var titlebar_stylebox: StyleBox
var effect_slots: Dictionary = {}
var requirement_slots: Dictionary = {}
var compact := false
var _compact_summary: Label
var _detail_rows: Array[Control] = []


func _init(title_text: String, goap_script: Script = null) -> void:
	titlebar_stylebox = get_theme_stylebox("titlebar").duplicate()
	add_theme_stylebox_override("titlebar", titlebar_stylebox)
	title = title_text
	self.goap_script = goap_script
	draggable = false
	selectable = false
	if Engine.is_editor_hint():
		if goap_script:
			var script_button := Button.new()
			var editor := Engine.get_singleton("EditorInterface")
			var control := editor.call("get_base_control") as Control
			script_button.icon = control.get_theme_icon("Script", "EditorIcons")
			script_button.pressed.connect(_on_script_button_pressed)
			get_titlebar_hbox().add_child(script_button)


func add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate.a = 0.65
	add_child(label)


## Explicit values prevent an unchecked false requirement looking unsatisfied.
func add_facts(facts: GoapWorldState, world: GoapWorldState = null, ports: String = "") -> void:
	for key in facts.keys():
		var row := HBoxContainer.new()
		row.set_meta("fact", key)
		row.set_meta("value", facts.get_state(key))
		var label := Label.new()
		label.text = "%s = %s" % [key, str(facts.get_state(key))]
		label.custom_minimum_size.x = 190
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		if world != null:
			var met: bool = world.get_state(key) == facts.get_state(key)
			row.set_meta("satisfied", met)
			var status := Label.new()
			status.text = "Met" if met else "Needed"
			status.modulate = Color(0.55, 0.9, 0.6) if met else Color(1.0, 0.78, 0.4)
			row.add_child(status)
			row.tooltip_text = "Current: %s | Required: %s" % [
				str(world.get_state(key)),
				str(facts.get_state(key))
			]
		add_child(row)
		var slot := row.get_index()
		if ports == "effects":
			effect_slots[key] = slot
			set_slot(slot, true, TYPE_BOOL, Color("78bdec"), false, TYPE_BOOL, Color.WHITE)
		elif ports == "requirements":
			requirement_slots[key] = slot
			var color := Color("8ec79b") if row.get_meta("satisfied", false) else Color("e3b776")
			set_slot(slot, false, TYPE_BOOL, Color.WHITE, true, TYPE_BOOL, color)


## Port indices are not child indices: section headings do not have ports.
func fact_port(key: StringName, output: bool) -> int:
	var slots := requirement_slots if output else effect_slots
	if not slots.has(key):
		return -1
	if compact:
		return 0
	var count := get_output_port_count() if output else get_input_port_count()
	for port in count:
		var slot := get_output_port_slot(port) if output else get_input_port_slot(port)
		if slot == slots[key]:
			return port
	return -1


func requirement_value(key: StringName) -> bool:
	var slot: int = requirement_slots[key]
	var row: Control = _detail_rows[slot] if compact else get_child(slot)
	return row.get_meta("value")


## Keep the fact rows for inspection while presenting one port per side in overview.
func make_compact() -> void:
	compact = true
	selectable = true
	custom_minimum_size.x = 150
	for child in get_titlebar_hbox().get_children():
		if child is Button:
			child.hide()
		elif child is Label:
			child.add_theme_font_size_override("font_size", 14)
	clear_all_slots()
	var needed := 0
	for slot: int in requirement_slots.values():
		if not get_child(slot).get_meta("satisfied", false):
			needed += 1
	var details := PackedStringArray([title])
	for child in get_children():
		if child is Label:
			details.append(child.text)
		elif child.has_meta("fact"):
			details.append("%s = %s" % [child.get_meta("fact"), child.get_meta("value")])
		if child is Control:
			_detail_rows.append(child)
			remove_child(child)
	_compact_summary = Label.new()
	_compact_summary.text = "%d needed / %d met" % [needed, requirement_slots.size() - needed]
	_compact_summary.add_theme_font_size_override("font_size", 12)
	_compact_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_compact_summary)
	var color := Color("e3b776") if needed > 0 else Color("8ec79b")
	_compact_summary.add_theme_color_override("font_color", color)
	set_slot(
		_compact_summary.get_index(),
		not effect_slots.is_empty(),
		TYPE_BOOL,
		Color("78bdec"),
		not requirement_slots.is_empty(),
		TYPE_BOOL,
		color
	)
	tooltip_text = "\n".join(details) + "\nSelect to inspect conditions and effects."
	reset_size()


func show_details(container: VBoxContainer) -> void:
	for child in container.get_children():
		child.free()
	var heading := Label.new()
	heading.text = title
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(heading)
	var rows: Array = _detail_rows if compact else get_children()
	for child in rows:
		if child == _compact_summary or not child is Control:
			continue
		var copy := child.duplicate() as Control
		container.add_child(copy)
		copy.show()
	if goap_script != null and Engine.is_editor_hint():
		var open_script := Button.new()
		open_script.text = "Open script"
		open_script.pressed.connect(_on_script_button_pressed)
		container.add_child(open_script)


func set_color(color: Color) -> void:
	if is_inside_tree():
		var tween := get_tree().create_tween()
		tween.tween_property(titlebar_stylebox, "bg_color", color, 0.2)
	else:
		titlebar_stylebox.bg_color = color


func _on_script_button_pressed() -> void:
	if Engine.is_editor_hint() and goap_script != null:
		var editor := Engine.get_singleton("EditorInterface")
		editor.call("edit_script", goap_script)
		editor.call("set_main_screen_editor", "Script")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for row in _detail_rows:
			row.free()
