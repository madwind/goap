extends Node

var goap_debugger := preload("goap_debugger.tscn").instantiate()
var window: Window
var enable := true

@onready var gui_embed_subwindows := get_viewport().gui_embed_subwindows


func _enter_tree() -> void:
	show_window()
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)


func _on_node_added(agent: Node) -> void:
	if agent is GoapAgent:
		goap_debugger.add_agent(agent)


func _on_node_removed(agent: Node) -> void:
	if agent is GoapAgent:
		goap_debugger.remove_agent(agent)


func show_window() -> void:
	if not window:
		window = Window.new()
		get_viewport().gui_embed_subwindows = false
		window.title = "Goap"
		window.add_child(goap_debugger)
		window.close_requested.connect(func() -> void:
			window.visible = false
			get_viewport().gui_embed_subwindows = gui_embed_subwindows
		)
		add_child(window)
	window.popup_centered_ratio()
	if DisplayServer.get_screen_count() > 1:
		window.current_screen = 1
