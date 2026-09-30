@tool
extends VBoxContainer

signal toggle_window

const EditorData = preload("res://addons/goap/visual_editor/goap_editor_data.gd")
const DefinitionBrowser = preload("res://addons/goap/visual_editor/goap_definition_browser.gd")
const PREVIEW_NODE_LIMIT := 1000
var runtime_view: VBoxContainer
var definitions: HSplitContainer
var workspace_notice: Label
var template_dialog: ConfirmationDialog
var template_filename: LineEdit
var template_notice: Label
var template_kind := "Action"
var fact_controls: Dictionary = {}
var fact_rows: Dictionary = {}
var _preview_fact_keys: Array[StringName] = []
var source_agent: GoapAgent
var preview_agent: GoapAgent
var graph_nodes: Array[GraphNode] = []
var _layout_generation := 0
var _refreshing := false
var _pending_connections: Array[Dictionary] = []
var _preview_results: Array[Dictionary] = []
var _status_summary := ""
var _dependency_nodes: Dictionary = {}

@onready var graph_edit: GraphEdit = $Content/PreviewArea/GraphEdit
@onready var world_state_container: VBoxContainer = $"Content/PreviewArea/StatePanel/Surface/Margin/Tabs/World facts/FactScroll/WorldStateContainer"
@onready var fact_search: LineEdit = $"Content/PreviewArea/StatePanel/Surface/Margin/Tabs/World facts/Filters/FactSearch"
@onready var true_only: CheckButton = $"Content/PreviewArea/StatePanel/Surface/Margin/Tabs/World facts/Filters/TrueOnly"
@onready var fact_empty: Label = $"Content/PreviewArea/StatePanel/Surface/Margin/Tabs/World facts/FactEmpty"
@onready var window_button: Button = $Header/Window
@onready var agent_picker: OptionButton = $Toolbar/AgentPicker
@onready var mode_tabs: TabBar = $Header/ModeTabs
@onready var status_label: Label = $Status
@onready var goal_search: LineEdit = $Content/GoalSidebar/GoalSearch
@onready var goal_list: ItemList = $Content/GoalSidebar/GoalList
@onready var goal_summary: Label = $Content/GoalSidebar/GoalSummary
@onready var view_picker: OptionButton = $ViewOptions/ViewPicker
@onready var plan_browser = $Content/PreviewArea/PlanBrowser
@onready var inspector_tabs: TabContainer = $Content/PreviewArea/StatePanel/Surface/Margin/Tabs
@onready var compact_toggle: CheckButton = $ViewOptions/Compact


func _ready() -> void:
	_setup_workbench()
	window_button.icon = EditorInterface.get_base_control().get_theme_icon("MakeFloating", "EditorIcons")
	$Toolbar/Reload.pressed.connect(reload)
	$Toolbar/Frame.pressed.connect(frame_graph)
	$Toolbar/Arrange.pressed.connect(
		func() -> void: _layout_graph.call_deferred(_layout_generation)
	)
	window_button.pressed.connect(func() -> void: toggle_window.emit())
	agent_picker.item_selected.connect(_on_agent_selected)
	goal_search.text_changed.connect(func(_query: String) -> void:
		_populate_goal_list()
		build_tree())
	goal_list.item_selected.connect(_on_goal_selected)
	fact_search.text_changed.connect(func(_query: String) -> void: _filter_fact_rows())
	true_only.toggled.connect(func(_enabled: bool) -> void: _filter_fact_rows())
	view_picker.add_item("Plans")
	view_picker.add_item("Dependency graph")
	view_picker.item_selected.connect(_on_view_selected)
	compact_toggle.toggled.connect(
		func(_enabled: bool) -> void:
			_clear_graph()
			_render_graph()
	)
	plan_browser.inspector = $"Content/PreviewArea/StatePanel/Surface/Margin/Tabs/Step details/Inspector"
	plan_browser.step_inspected.connect(func() -> void: inspector_tabs.current_tab = 0)
	plan_browser.show_all_goals_changed.connect(build_tree)
	plan_browser.preview_fact_changed.connect(set_preview_fact)
	inspector_tabs.set_tab_title(0, "Details")
	inspector_tabs.set_tab_title(1, "World state")
	view_picker.select(0)
	_on_view_selected(0)
	EditorInterface.get_selection().selection_changed.connect(handle_selection)
	visibility_changed.connect(_on_visibility_changed)
	refresh_agents.call_deferred()


func refresh_agents() -> void:
	if not is_node_ready() or _refreshing:
		return
	_refreshing = true
	var scene := EditorInterface.get_edited_scene_root()
	var available: Array[GoapAgent] = []
	_collect_agents(scene, available)
	agent_picker.clear()
	for candidate in available:
		agent_picker.add_item(str(scene.get_path_to(candidate)))
		agent_picker.set_item_metadata(agent_picker.item_count - 1, candidate.get_instance_id())
	agent_picker.disabled = available.is_empty()
	if available.is_empty():
		source_agent = null
		_clear_preview()
		status_label.text = "No GOAP agent in this scene. Open world.tscn or a scene containing GoapAgent."
	else:
		var target := _selected_agent()
		if target == null or not available.has(target):
			target = source_agent if is_instance_valid(source_agent) and available.has(
				source_agent
			) else available[0]
		agent_picker.select(available.find(target))
		if not target.property_list_changed.is_connected(_on_agent_properties_changed):
			target.property_list_changed.connect(_on_agent_properties_changed)
		if source_agent != target or preview_agent == null:
			source_agent = target
			reload()
	_refreshing = false


func handle_selection() -> void:
	refresh_agents()


func _on_agent_properties_changed() -> void:
	refresh_agents.call_deferred()


func reload() -> void:
	if not is_instance_valid(source_agent):
		refresh_agents()
		return
	_clear_preview()
	if source_agent.goap_script_folder.is_empty():
		status_label.text = "Set goap_script_folder to the folder containing actions/ and goals/."
		return
	preview_agent = source_agent.get_script().new() as GoapAgent
	preview_agent.goap_script_folder = source_agent.goap_script_folder
	preview_agent.fact_key_script = source_agent.fact_key_script
	preview_agent.debug = true
	preview_agent.init_goap(source_agent.goap_script_folder)
	preview_agent.world_state.state_changed.connect(_on_preview_state_changed)
	_populate_goal_list()
	_preview_fact_keys = EditorData.fact_keys(preview_agent)
	_rebuild_fact_controls()
	definitions.set_agent(preview_agent, _preview_fact_keys)
	workspace_notice.text = "Script definitions - Structural preview with priority and base costs; runtime availability and dynamic cost are evaluated during play."
	build_tree()


func _populate_goal_list(preferred_id := "") -> void:
	var selected_id := preferred_id
	if selected_id.is_empty() and preview_agent != null and not goal_list.get_selected_items().is_empty():
		var old_index: int = goal_list.get_item_metadata(goal_list.get_selected_items()[0])
		if old_index < preview_agent.goals.size():
			selected_id = preview_agent.goals[old_index].get_id()
	goal_list.clear()
	if preview_agent == null:
		goal_summary.text = "Select an Agent to browse goals."
		return
	var selected := -1
	for index in preview_agent.goals.size():
		var goal := preview_agent.goals[index]
		if not goal_search.text.is_empty() and not (String(goal.name) + " " + goal.get_id()).containsn(goal_search.text):
			continue
		var row := goal_list.item_count
		goal_list.add_item(String(goal.name).to_snake_case().capitalize())
		goal_list.set_item_metadata(row, index)
		if goal.get_id() == selected_id:
			selected = row
	_refresh_goal_statuses()
	goal_summary.text = "%d / %d goals" % [goal_list.item_count, preview_agent.goals.size()]
	if goal_list.item_count > 0:
		goal_list.select(maxi(selected, 0))


func _on_goal_selected(index: int) -> void:
	# A deliberate goal selection takes precedence over the all-goals overview.
	plan_browser.show_all_goals.set_pressed_no_signal(false)
	build_tree()
	if preview_agent != null and index >= 0 and index < goal_list.item_count:
		plan_browser.inspect_goal(preview_agent.goals[goal_list.get_item_metadata(index)])


func build_tree() -> void:
	_sync_fact_controls()
	_refresh_goal_statuses()
	_clear_graph()
	_preview_results.clear()
	_status_summary = ""
	if preview_agent == null:
		return
	if preview_agent.goals.is_empty():
		plan_browser.clear()
		status_label.text = "No goals defined. Create a Goal script from Definitions or add one in the agent's goals/ folder."
		return
	if goal_list.get_selected_items().is_empty() and not plan_browser.show_all_goals.button_pressed:
		plan_browser.clear()
		status_label.text = "No matching goal. Clear the goal search to see its plans."
		return
	var expanded := 0
	var candidates := 0
	var all_satisfied := true
	var complete := true
	var displayed := 0
	for goal_index in preview_agent.goals.size():
		if not plan_browser.show_all_goals.button_pressed and goal_index != goal_list.get_item_metadata(goal_list.get_selected_items()[0]):
			continue
		displayed += 1
		var goal := preview_agent.goals[goal_index]
		var planner := GoapPlanner.new(preview_agent.actions)
		var action_snapshot := planner.create_action_snapshot()
		var result := GoapPlanner.search_snapshot(
			preview_agent.world_state.to_dictionary(),
			goal.goal_state.to_dictionary(),
			action_snapshot,
			PREVIEW_NODE_LIMIT
		)
		expanded += result.statistics.expanded_nodes
		candidates += result.statistics.candidate_count
		complete = complete and result.statistics.search_complete
		all_satisfied = all_satisfied and preview_agent.world_state.satisfies(goal.goal_state)
		_preview_results.append({ "goal": goal, "actions": planner.actions, "search": result })
	var preview_labels: Dictionary = {}
	for key in _preview_fact_keys:
		preview_labels[key] = preview_agent.get_world_state_label(key)
	for action: GoapAction in preview_agent.actions:
		for key in action.preconditions.keys():
			if not preview_labels.has(key):
				preview_labels[key] = preview_agent.get_world_state_label(key)
	plan_browser.set_results(_preview_results, preview_agent.world_state, preview_labels)
	status_label.text = "%d goal(s) · %d plan(s)" % [displayed, candidates]
	status_label.tooltip_text = "%d search nodes expanded" % expanded
	if all_satisfied:
		status_label.text = "Goals already satisfied. Toggle world facts to reveal action dependencies."
	elif candidates == 0:
		status_label.text = "No complete plan from these facts. Check the Needed conditions."
	if not complete:
		status_label.text += " | Preview node limit reached."
	_status_summary = status_label.text
	_update_view_status()
	_render_graph()


func _refresh_goal_statuses() -> void:
	if preview_agent == null:
		return
	for row in goal_list.item_count:
		var goal: GoapGoal = preview_agent.goals[goal_list.get_item_metadata(row)]
		var missing := goal.goal_state.difference(preview_agent.world_state)
		var active := missing.size() > 0
		var state_label := "Active" if active else "Satisfied"
		var priority := goal.get_priority(preview_agent.world_state.duplicate())
		goal_list.set_item_text(row, "%s · Priority %.1f" % [String(goal.name).to_snake_case().capitalize(), priority])
		goal_list.set_item_custom_fg_color(row, Color("8ec79b") if active else Color("a2adbd"))
		var activation_lines := PackedStringArray()
		for key in goal.goal_state.keys():
			activation_lines.append("%s = %s" % [key, str(not goal.goal_state.get_state(key))])
		goal_list.set_item_tooltip(row, "%s\n%s\nActivate preview by setting any one of: %s" % [
			goal.get_id(), state_label, ", ".join(activation_lines)
		])


func frame_graph() -> void:
	if graph_nodes.is_empty():
		return
	var bounds := Rect2(graph_nodes[0].position_offset, graph_nodes[0].size)
	for node in graph_nodes:
		bounds = bounds.merge(Rect2(node.position_offset, node.size))
	for route in graph_edit.routes:
		for point in route:
			bounds = bounds.expand(point)
	var usable := graph_edit.size - Vector2(64, 80)
	var fit := minf(usable.x / maxf(bounds.size.x, 1), usable.y / maxf(bounds.size.y, 1))
	graph_edit.zoom = clampf(fit, graph_edit.zoom_min, 1.0)
	graph_edit.scroll_offset = bounds.get_center() * graph_edit.zoom - graph_edit.size / 2.0


func add_node(node: GraphNode) -> void:
	if view_picker.selected == 1:
		node.selectable = true
		if compact_toggle.button_pressed:
			node.make_compact()
		node.node_selected.connect(
			func() -> void:
				node.show_details(plan_browser.inspector)
				inspector_tabs.current_tab = 0
		)
	graph_edit.add_child(node, true)
	graph_nodes.append(node)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh_agents.call_deferred()
		_layout_graph.call_deferred(_layout_generation)


func _collect_agents(node: Node, result: Array[GoapAgent]) -> void:
	if node == null:
		return
	if node is GoapAgent:
		result.append(node)
	for child in node.get_children():
		_collect_agents(child, result)


func _selected_agent() -> GoapAgent:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() != 1:
		return null
	var node: Node = selected[0]
	var ancestor := node
	while ancestor != null:
		if ancestor is GoapAgent:
			return ancestor
		ancestor = ancestor.get_parent()
	var descendants: Array[GoapAgent] = []
	_collect_agents(node, descendants)
	return descendants[0] if descendants.size() == 1 else null


func _on_agent_selected(index: int) -> void:
	var selected := instance_from_id(agent_picker.get_item_metadata(index)) as GoapAgent
	if is_instance_valid(selected):
		source_agent = selected
		reload()


func _clear_graph() -> void:
	_layout_generation += 1
	graph_edit.clear_connections()
	_pending_connections.clear()
	graph_edit.routes.clear()
	_dependency_nodes.clear()
	for node in graph_nodes:
		node.free()
	graph_nodes.clear()
	if graph_edit.visible:
		plan_browser._clear_inspector()


func _clear_preview() -> void:
	template_dialog.hide()
	workspace_notice.text = "Select an Agent to browse definitions and explore hypothetical plans."
	definitions.set_agent(null)
	fact_controls.clear()
	_preview_fact_keys.clear()
	fact_rows.clear()
	fact_empty.hide()
	_clear_graph()
	_preview_results.clear()
	_status_summary = ""
	plan_browser.clear()
	if is_instance_valid(preview_agent):
		preview_agent.free()
	preview_agent = null
	goal_list.clear()
	goal_summary.text = "Select an Agent to browse goals."
	fact_search.clear()
	true_only.set_pressed_no_signal(false)
	for child in world_state_container.get_children():
		child.free()


func _on_view_selected(_index: int) -> void:
	plan_browser.visible = view_picker.selected == 0
	graph_edit.visible = view_picker.selected != 0
	$Toolbar/Frame.visible = mode_tabs.current_tab == 1 and graph_edit.visible
	$Toolbar/Arrange.visible = mode_tabs.current_tab == 1 and graph_edit.visible
	compact_toggle.visible = view_picker.selected == 1
	inspector_tabs.current_tab = 1 if graph_edit.visible else 0
	_update_view_status()
	_clear_graph()
	_render_graph()


func _update_view_status() -> void:
	if _status_summary.is_empty():
		return
	var hints := [
		"Follow the execution order from top to bottom. Select an action for details.",
		"Shared action dependencies. See Plans for execution order. Green = met; amber = needed."
	]
	status_label.text = _status_summary + " - " + hints[view_picker.selected]


func _render_graph() -> void:
	if view_picker.selected == 0 or preview_agent == null:
		return
	for preview in _preview_results:
		var result: Dictionary = preview.search
		var root := GoapGoalGraphNode.new(preview.goal, preview_agent.world_state)
		root.tooltip_text = str(result.statistics)
		add_node(root)
		_build_dependencies(root, preview.actions)
	_layout_graph.call_deferred(_layout_generation)


## An action has one node, regardless of how many goals or search orders use it.
## Only its own preconditions belong here, without regressed branch states.
func _build_dependencies(root: GoapBaseGraphNode, actions: Array[GoapAction]) -> void:
	var providers: Dictionary = {}
	for action in actions:
		for key in action.effects.keys():
			var fact := JSON.stringify([key, action.effects.get_state(key)])
			if not providers.has(fact):
				providers[fact] = []
			providers[fact].append(action)
	var queue: Array[GoapBaseGraphNode] = [root]
	var cursor := 0
	while cursor < queue.size():
		var consumer := queue[cursor]
		cursor += 1
		for key: StringName in consumer.requirement_slots:
			var value := consumer.requirement_value(key)
			# Facts supplied by the current world need no preparation branch.
			if preview_agent.world_state.get_state(key) == value:
				continue
			for action: GoapAction in providers.get(JSON.stringify([key, value]), []):
				var id := action.get_id()
				if not _dependency_nodes.has(id):
					var node := GoapActionGraphNode.new(action, preview_agent.world_state)
					node.set_meta("action_id", id)
					add_node(node)
					_dependency_nodes[id] = node
					queue.append(node)
				_pending_connections.append(
					{ "from": consumer, "to": _dependency_nodes[id], "fact": key }
				)


func _layout_graph(generation: int) -> void:
	# GraphNode ports are cached during container layout, after entering the tree.
	if not is_visible_in_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _layout_generation or not is_visible_in_tree():
		return
	graph_edit.clear_connections()
	_arrange_dependencies()
	for connection in _pending_connections:
		var from: GraphNode = connection.from
		var to: GraphNode = connection.to
		var from_port: int = from.fact_port(connection.fact, true)
		var to_port: int = to.fact_port(connection.fact, false)
		if from_port >= 0 and from_port < from.get_output_port_count() and to_port >= 0 and to_port < to.get_input_port_count():
			if not graph_edit.is_node_connected(from.name, from_port, to.name, to_port):
				graph_edit.connect_node(from.name, from_port, to.name, to_port)
	await get_tree().process_frame
	if generation == _layout_generation and is_inside_tree():
		_focus_goal()


## Keep layout independent of GraphEdit's generic node arranger.
func _arrange_dependencies() -> void:
	var layout = preload("res://addons/goap/visual_editor/goap_graph_layout.gd").new()
	graph_edit.routes = layout.arrange(graph_nodes, _pending_connections)


func _focus_goal() -> void:
	if graph_nodes.is_empty():
		return
	# Keep text readable by default. Frame All is an explicit overview operation.
	graph_edit.zoom = 1.0
	var top := graph_nodes[0].position_offset.y
	for node in graph_nodes:
		top = minf(top, node.position_offset.y)
	graph_edit.scroll_offset = Vector2(graph_nodes[0].position_offset.x - 32, top - 72)


func _notification(what: int) -> void:
	# Removing the dock to place it in a window must preserve its what-if state.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(preview_agent):
		preview_agent.free()
		preview_agent = null


func _setup_workbench() -> void:
	for title in ["Definitions", "Preview", "Runtime"]:
		mode_tabs.add_tab(title)
	mode_tabs.tab_changed.connect(_on_mode_selected)
	$Toolbar/Reload.tooltip_text = "Reload saved scripts and reset all preview world state."
	workspace_notice = Label.new()
	workspace_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workspace_notice.text = "Select an Agent to browse script definitions and explore hypothetical plans."
	add_child(workspace_notice)
	move_child(workspace_notice, 2)
	definitions = DefinitionBrowser.new()
	definitions.name = "Definitions"
	add_child(definitions)
	definitions.hide()
	definitions.create_requested.connect(func(kind: String) -> void:
		_show_template_dialog(kind))
	definitions.definition_changed.connect(func(kind: String, id: String) -> void:
		reload()
		definitions.select_definition(kind, id)
		workspace_notice.text = "Saved action definition to GDScript: %s" % id)
	runtime_view = preload("res://addons/goap/debugger/goap_remote_view.gd").new()
	runtime_view.name = "Runtime"
	add_child(runtime_view)
	runtime_view.hide()
	template_dialog = ConfirmationDialog.new()
	template_dialog.min_size = Vector2i(360, 120)
	template_dialog.dialog_hide_on_ok = false
	template_dialog.ok_button_text = "Create script"
	var form := VBoxContainer.new()
	template_dialog.add_child(form)
	template_filename = LineEdit.new()
	template_filename.tooltip_text = "Enter a snake_case file name without .gd."
	form.add_child(template_filename)
	template_notice = Label.new()
	template_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	template_notice.visible = false
	form.add_child(template_notice)
	template_dialog.confirmed.connect(_create_template)
	add_child(template_dialog)
	_on_mode_selected(0)


func _on_mode_selected(index: int) -> void:
	mode_tabs.current_tab = index
	var preview := index == 1
	definitions.visible = index == 0
	runtime_view.visible = index == 2
	$Toolbar.visible = index != 2
	workspace_notice.visible = index != 2
	$ViewOptions.visible = preview
	$Content.visible = preview
	$Status.visible = preview
	$Toolbar/Frame.visible = preview and graph_edit.visible
	$Toolbar/Arrange.visible = preview and graph_edit.visible
	if index == 0:
		definitions.set_agent(preview_agent, _preview_fact_keys)
	else:
		_layout_graph.call_deferred(_layout_generation)


func _rebuild_fact_controls() -> void:
	for child in world_state_container.get_children():
		child.free()
	fact_controls.clear()
	fact_rows.clear()
	var hint := Label.new()
	hint.text = "Preview world state\nChecked = True - Unchecked = False\nSource = Fact provider\nRefs = Find references"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_state_container.add_child(hint)
	for key in _preview_fact_keys:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var choice := CheckBox.new()
		choice.text = preview_agent.get_world_state_label(key)
		choice.add_theme_font_size_override("font_size", 14)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		choice.toggled.connect(func(enabled: bool) -> void: set_preview_fact(key, enabled))
		row.add_child(choice)
		if not preview_agent.get_world_state_sources(key).is_empty():
			var source := Button.new()
			source.text = "Source"
			source.add_theme_font_size_override("font_size", 14)
			source.flat = true
			source.tooltip_text = "Open the provider that supplies this fact"
			source.pressed.connect(func() -> void:
				_on_mode_selected(0)
				definitions.select_definition("Fact", key))
			row.add_child(source)
		var references := Button.new()
		references.text = "Refs"
		references.flat = true
		references.tooltip_text = String(key) + " - Find references"
		references.pressed.connect(func() -> void:
			_on_mode_selected(0)
			definitions.select_definition("Fact", key))
		row.add_child(references)
		world_state_container.add_child(row)
		fact_controls[key] = choice
		fact_rows[key] = row
	_sync_fact_controls()


func _sync_fact_controls() -> void:
	if preview_agent == null:
		return
	for key: StringName in fact_controls:
		var value := preview_agent.world_state.get_state(key)
		fact_controls[key].set_pressed_no_signal(value)
		fact_controls[key].tooltip_text = "%s = %s" % [key, str(value)]
	_filter_fact_rows()


func _filter_fact_rows() -> void:
	var query := fact_search.text.strip_edges()
	var shown := 0
	for key: StringName in fact_rows:
		var choice: CheckBox = fact_controls[key]
		var matches := query.is_empty() or (String(key) + " " + choice.text).containsn(query)
		fact_rows[key].visible = matches and (not true_only.button_pressed or choice.button_pressed)
		if fact_rows[key].visible:
			shown += 1
	fact_empty.visible = not fact_rows.is_empty() and shown == 0


## Replace only the detached preview state; never mutate the edited scene Agent.
func set_preview_fact(key: StringName, value: bool) -> void:
	if preview_agent == null:
		return
	var facts := preview_agent.world_state.to_dictionary()
	facts[key] = value
	_replace_preview_state(facts)
	_on_preview_state_changed()


func _replace_preview_state(facts: Dictionary[StringName, bool]) -> void:
	if preview_agent.world_state.state_changed.is_connected(_on_preview_state_changed):
		preview_agent.world_state.state_changed.disconnect(_on_preview_state_changed)
	preview_agent.world_state = GoapWorldState.new(facts)
	preview_agent.world_state.state_changed.connect(_on_preview_state_changed)


func _on_preview_state_changed() -> void:
	var active_tab := inspector_tabs.current_tab
	build_tree()
	inspector_tabs.current_tab = active_tab


func _show_template_dialog(kind: String) -> void:
	if preview_agent == null or source_agent.goap_script_folder.is_empty():
		return
	template_kind = kind
	template_dialog.title = "New " + kind
	template_filename.clear()
	template_notice.visible = false
	template_dialog.size = template_dialog.min_size
	template_dialog.popup_centered(template_dialog.min_size)
	template_filename.grab_focus()


func _create_template() -> void:
	if preview_agent == null:
		template_notice.text = "The selected Agent is no longer available."
		template_notice.visible = true
		return
	var filename := template_filename.text.strip_edges()
	var id := EditorData.template_id(filename)
	var items: Array = preview_agent.actions if template_kind == "Action" else preview_agent.goals
	for item in items:
		if item.get_id() == id:
			template_notice.text = "The ID '%s' already exists. Choose a different file name." % id
			template_notice.visible = true
			return
	var result := EditorData.create_template(source_agent.goap_script_folder, template_kind, filename)
	if result.has("error"):
		template_notice.text = result.error
		template_notice.visible = true
		return
	template_dialog.hide()
	EditorInterface.get_resource_filesystem().update_file(result.path)
	var previous_facts := preview_agent.world_state.to_dictionary()
	var previous_keys := _preview_fact_keys.duplicate()
	var previous_goal := ""
	if not goal_list.get_selected_items().is_empty():
		previous_goal = preview_agent.goals[goal_list.get_item_metadata(goal_list.get_selected_items()[0])].get_id()
	reload()
	_replace_preview_state(previous_facts)
	for key in previous_keys:
		if not _preview_fact_keys.has(key):
			_preview_fact_keys.append(key)
	_preview_fact_keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_populate_goal_list(previous_goal)
	_rebuild_fact_controls()
	build_tree()
	definitions.set_agent(preview_agent, _preview_fact_keys)
	definitions.select_definition(template_kind, id)
	workspace_notice.text = "Created %s. Save your script changes, then Reload." % result.path
	EditorInterface.edit_script(load(result.path))
	EditorInterface.set_main_screen_editor("Script")
