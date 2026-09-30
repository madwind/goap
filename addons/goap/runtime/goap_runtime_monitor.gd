class_name GoapRuntimeMonitor
extends CanvasLayer
## Reusable runtime window. Subclasses can supply authored tabs and a performance
## extension; other clients can register/unregister pages at runtime.

@export var performance_page_path: NodePath
@export var show_on_ready := true
@export var include_inspector_page := true
@onready var panel: PanelContainer = $RuntimeWindow/RuntimePanel
@onready var tabs: TabContainer = $RuntimeWindow/RuntimePanel/Column/Tabs
@onready var mode_button: Button = $RuntimeWindow/RuntimePanel/Column/Header/Mode
@onready var window: Window = $RuntimeWindow
@onready var performance: VBoxContainer = get_node_or_null(performance_page_path) as VBoxContainer

var pages: Array[Control] = []
var page_titles: Array[String] = []
var page_windows: Dictionary = {}
var inspector_page: Control
var inspector: Node
var _local_debugger: Control


func _ready() -> void:
	get_tree().root.gui_embed_subwindows = false
	for child in tabs.get_children():
		if child is Control:
			register_page(child, child.name)
	if performance == null:
		var page := preload("goap_performance_monitor.tscn").instantiate()
		register_page(page, "Performance")
		performance = page.get_node("Performance/Column")
	if include_inspector_page:
		inspector_page = MarginContainer.new()
		inspector_page.name = "GOAP"
		register_page(inspector_page, "GOAP")
	tabs.drag_to_rearrange_enabled = true
	mode_button.pressed.connect(
		func() -> void:
			var page := tabs.get_current_tab_control()
			if page != null:
				detach_tab(pages.find(page))
	)
	panel.get_node("Column/Header/Hide").pressed.connect(hide_monitor)
	window.close_requested.connect(hide_monitor)
	inspector = get_node_or_null("/root/GoapInspector")
	if inspector_page != null and inspector != null:
		inspector.attach_to(inspector_page)
	elif inspector_page != null:
		# Explicit scene instances also work without enabling the editor plugin.
		_local_debugger = preload("../debugger/goap_debugger.tscn").instantiate()
		inspector_page.add_child(_local_debugger)
		get_tree().node_added.connect(_observe_node)
		get_tree().node_removed.connect(_forget_node)
		_scan_agents(get_tree().root)
	if show_on_ready:
		show_monitor.call_deferred()


## Returns a stable handle, independent of tab order. The monitor owns the page
## until unregister_page() transfers it back to the caller.
func register_page(page: Control, title: String) -> int:
	var existing := pages.find(page)
	if existing >= 0:
		return existing
	var index := pages.size()
	pages.append(page)
	page_titles.append(title)
	if page.get_parent() == null:
		tabs.add_child(page)
	elif page.get_parent() != tabs:
		page.reparent(tabs, false)
	tabs.set_tab_title(tabs.get_tab_idx_from_control(page), title)
	mode_button.disabled = false
	return index


## The caller must reparent or free the returned page. Handles are not reused.
func unregister_page(index: int) -> Control:
	if index < 0 or index >= pages.size() or not is_instance_valid(pages[index]):
		return null
	var page := pages[index]
	# Built-in pages are owned for the lifetime of the monitor.
	if page == inspector_page or page == performance or page.is_ancestor_of(performance):
		return null
	page.get_parent().remove_child(page)
	if page_windows.has(index):
		page_windows[index].hide()
		page_windows[index].queue_free()
		page_windows.erase(index)
	pages[index] = null
	mode_button.disabled = tabs.get_tab_count() == 0
	return page


func _scan_agents(node: Node) -> void:
	_observe_node(node)
	for child in node.get_children():
		_scan_agents(child)


func _observe_node(node: Node) -> void:
	if node is GoapAgent:
		_local_debugger.add_agent(node)


func _forget_node(node: Node) -> void:
	if node is GoapAgent and is_instance_valid(_local_debugger):
		_local_debugger.remove_agent(node)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_observe_node):
		get_tree().node_added.disconnect(_observe_node)
		get_tree().node_removed.disconnect(_forget_node)
	if inspector_page != null and is_instance_valid(inspector):
		inspector.release_from(inspector_page)


func detach_tab(index: int) -> void:
	if index < 0 or index >= pages.size() or not is_instance_valid(pages[index]):
		return
	if page_windows.has(index):
		show_tab(index)
		return
	var floating := Window.new()
	floating.title = "Runtime monitor · " + page_titles[index]
	floating.size = Vector2i(1280, 800)
	floating.min_size = Vector2i(1000, 620)
	floating.visible = false
	floating.transient = false
	add_child(floating)
	var column := VBoxContainer.new()
	floating.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dock_button := Button.new()
	dock_button.text = "Dock in runtime monitor"
	dock_button.focus_mode = Control.FOCUS_NONE
	dock_button.pressed.connect(dock_tab.bind(index))
	column.add_child(dock_button)
	pages[index].reparent(column, false)
	pages[index].size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages[index].show()
	page_windows[index] = floating
	floating.close_requested.connect(dock_tab.bind(index))
	mode_button.disabled = tabs.get_tab_count() == 0
	floating.popup_centered()


func dock_tab(index: int) -> void:
	if index < 0 or index >= pages.size() or not is_instance_valid(pages[index]):
		return
	if not page_windows.has(index):
		return
	var floating: Window = page_windows[index]
	pages[index].reparent(tabs, false)
	var tab_index := tabs.get_tab_idx_from_control(pages[index])
	tabs.set_tab_title(tab_index, page_titles[index])
	tabs.current_tab = tab_index
	page_windows.erase(index)
	floating.hide()
	floating.queue_free()
	mode_button.disabled = false
	show_monitor()


func show_monitor() -> void:
	if window.visible:
		window.grab_focus()
	else:
		window.popup_centered()
	for floating: Window in page_windows.values():
		floating.show()


func hide_monitor() -> void:
	window.hide()
	for floating: Window in page_windows.values():
		floating.hide()


func show_tab(index: int) -> void:
	if index < 0 or index >= pages.size() or not is_instance_valid(pages[index]):
		return
	show_monitor()
	if page_windows.has(index):
		page_windows[index].grab_focus()
	else:
		tabs.current_tab = tabs.get_tab_idx_from_control(pages[index])


