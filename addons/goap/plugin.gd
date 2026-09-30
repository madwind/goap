@tool
extends EditorPlugin

var visual_view := preload("visual_editor/goap_visual_view.tscn").instantiate()
var window: Window
var window_container: VBoxContainer
var enable := true
var debugger_plugin := preload("debugger/goap_editor_debugger.gd").new()
var export_plugin := preload("goap_export_plugin.gd").new()


func _enter_tree():
	add_export_plugin(export_plugin)
	debugger_plugin.session_added.connect(func(id: int, model: RefCounted) -> void:
		if visual_view.is_node_ready():
			visual_view.runtime_view.add_session(id, model))
	add_debugger_plugin(debugger_plugin)
	EditorInterface.get_editor_main_screen().add_child(visual_view)
	for id: int in debugger_plugin.sessions:
		visual_view.runtime_view.add_session(id, debugger_plugin.sessions[id])
	visual_view.hide()
	scene_changed.connect(_on_scene_changed)
	visual_view.refresh_agents.call_deferred()


func _ready() -> void:
	visual_view.toggle_window.connect(show_window)


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "GOAP"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("GraphEdit", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if is_instance_valid(visual_view) and visual_view.get_parent() == EditorInterface.get_editor_main_screen():
		visual_view.visible = visible


func show_window() -> void:
	visual_view.get_parent().remove_child(visual_view)
	if not window:
		window = Window.new()
		window.title = "Goap"
		window_container = VBoxContainer.new()
		window_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		window.add_child(window_container)
		window.close_requested.connect(
			func() -> void:
				window_container.remove_child(visual_view)
				if enable:
					EditorInterface.get_editor_main_screen().add_child(visual_view)
					EditorInterface.set_main_screen_editor("GOAP")
					visual_view.show()
				visual_view.window_button.show()
				window.hide()
		)
		EditorInterface.get_base_control().add_child(window)
	visual_view.window_button.hide()
	window_container.add_child(visual_view)
	visual_view.show()
	window.popup_centered_ratio()


func _on_scene_changed(_scene: Node) -> void:
	visual_view.refresh_agents.call_deferred()


func _exit_tree():
	remove_export_plugin(export_plugin)
	remove_debugger_plugin(debugger_plugin)
	enable = false
	if window:
		window.queue_free()
	if visual_view.get_parent() == EditorInterface.get_editor_main_screen():
		visual_view.queue_free()
