class_name GoapBaseGraphNode
extends GraphNode

var goap_script: Script
var titlebar_stylebox: StyleBox


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
			script_button.icon = EditorInterface.get_base_control().get_theme_icon("Script", "EditorIcons")
			script_button.pressed.connect(_on_script_button_pressed)
			get_titlebar_hbox().add_child(script_button)


func _on_script_button_pressed() -> void:
	if Engine.is_editor_hint():
		EditorInterface.edit_script(goap_script)


func new_state(key: String, value: bool) -> Control:
	var check_box := CheckBox.new()
	check_box.text = key
	check_box.button_pressed = value
	check_box.button_mask = 0
	return check_box


func set_color(color: Color) -> void:
	if is_inside_tree():
		var tween := get_tree().create_tween()
		tween.tween_property(titlebar_stylebox, "bg_color", color, 0.2)
	else:
		titlebar_stylebox.bg_color = color
