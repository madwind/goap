@tool
extends EditorPlugin

var visual_view := preload("visual_editor/goap_visual_view.tscn").instantiate()
var window: Window
var window_container: VBoxContainer
var enable := true
const AUTOLOAD_NAME = "GoapInspector"


func _ready() -> void:
	visual_view.toogle_window.connect(show_window)


func _enter_tree():
	add_autoload_singleton(AUTOLOAD_NAME, "debugger/goap_debugger_autoload.gd")
	add_control_to_bottom_panel(visual_view, "Goap")


func show_window() -> void:
	remove_control_from_bottom_panel(visual_view)
	if not window:
		window = Window.new()
		window.title = "Goap"
		window_container = VBoxContainer.new()
		window_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		window.add_child(window_container)
		window.close_requested.connect(func() -> void:
			window_container.remove_child(visual_view)
			if enable:
				add_control_to_bottom_panel(visual_view, "Goap")
			visual_view.window_button.show()
			window.hide()
			)
		EditorInterface.get_base_control().add_child(window)
	visual_view.window_button.hide()
	window_container.add_child(visual_view)
	window.popup_centered_ratio()


func _exit_tree():
	enable = false
	remove_control_from_bottom_panel(visual_view)
	remove_autoload_singleton(AUTOLOAD_NAME)
	if window:
		window.queue_free()
	visual_view.queue_free()
