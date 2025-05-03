@tool
extends Control
var agent_node: GoapAgent
var graph_nodes: Array[GoapBaseGraphNode]
var world_state_children: Array[CheckBox]
var window_button: Button
var current_agent: GoapAgent
@onready var graph_edit: GraphEdit = $GraphEdit
@onready var world_state_container: VBoxContainer = $PanelContainer/MarginContainer/WorldStateContainer

signal toogle_window


func _ready() -> void:
	var menu_hbox := graph_edit.get_menu_hbox()
	var reload_button := Button.new()
	reload_button.icon = EditorInterface.get_base_control().get_theme_icon("Reload", "EditorIcons")
	reload_button.pressed.connect(reload)
	menu_hbox.add_child(reload_button)

	window_button = Button.new()
	window_button.icon = EditorInterface.get_base_control().get_theme_icon("ExternalLink", "EditorIcons")
	window_button.pressed.connect(func() -> void: toogle_window.emit())
	menu_hbox.add_child(window_button)
	EditorInterface.get_selection().selection_changed.connect(handle_selection)


func handle_selection() -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.size() == 1 and selected_nodes[0] is GoapAgent and selected_nodes[0] != agent_node:
		agent_node = selected_nodes[0]
		reload()


func reload(agent: GoapAgent = null):
	if agent_node:
		for child in world_state_children:
			world_state_container.remove_child(child)
		world_state_children.clear()
		if !agent:
			agent = agent_node.get_script().new() as GoapAgent
			agent.debug = true
			agent.init_goap(agent_node.goap_script_folder)
			agent.world_state.state_changed.connect(func() -> void: build_tree(agent))
		build_tree(agent)
		build_world_state(agent)


func build_tree(agent: GoapAgent) -> void:
	for node in graph_nodes:
		graph_edit.remove_child(node)
	graph_nodes.clear()

	var goals := agent.goals
	var active_gaol = agent._planner.select_best_goal()
	for goal in goals:
		var root_node := GoapGoalGraphNode.new(goal)
		if active_gaol == goal:
			root_node.set_color(GoapTheme.COLOR_ACTIVE)
		add_and_record(root_node)
		var valid_plan_nodes: Array[GoapPlanNode] = []
		var invalid_plan_nodes: Array[GoapPlanNode] = []
		agent._planner.get_plan_from_goal(goal, valid_plan_nodes, invalid_plan_nodes)
		process_plan_nodes(valid_plan_nodes, agent, GoapTheme.COLOR_SUCCESS)
		process_plan_nodes(invalid_plan_nodes, agent, GoapTheme.COLOR_FAILED)
	graph_edit.arrange_nodes()


func process_plan_nodes(plan_nodes: Array[GoapPlanNode], agent: GoapAgent, color: Color) -> void:
	for plan_node in plan_nodes:
		var unsatisfied_node: GoapUnsatisfiedStateGraphNode = null
		var remaining_goals := agent.world_state.get_unsatisfied_goals(plan_node.remaining_goals)
		if remaining_goals.size() > 0:
			unsatisfied_node = GoapUnsatisfiedStateGraphNode.new(remaining_goals)
			add_and_record(unsatisfied_node)
		extra_plan(plan_node, unsatisfied_node, color)


func extra_plan(plan_node: GoapPlanNode, next_node: GoapBaseGraphNode, color: Color):
		if plan_node.goal:
			var goal_graph_nodes := graph_nodes.filter(func(node: GoapBaseGraphNode) -> bool: return node.title == plan_node.goal.name)
			if goal_graph_nodes.size() == 1 and next_node:
				var goal_graph_node := goal_graph_nodes[0] as GoapGoalGraphNode
				if color == GoapTheme.COLOR_SUCCESS:
					goal_graph_node.set_color(GoapTheme.COLOR_SUCCESS)
				graph_edit.connect_node(goal_graph_node.name, 0, next_node.name, 0)
			return
		var action_node := GoapActionGraphNode.new(plan_node.action, plan_node.remaining_goals)
		action_node.set_color(color)
		add_and_record(action_node)
		if next_node:
			graph_edit.connect_node(action_node.name, 0, next_node.name, 0)
		elif action_node.get_output_port_count() > 0:
			action_node.set_slot_enabled_right(action_node.get_output_port_slot(0), false)
		if plan_node.parent:
			extra_plan(plan_node.parent, action_node, color)


func build_world_state(agent: GoapAgent) -> void:
	for state in agent.world_state.keys():
		var check_box := CheckBox.new()
		check_box.text = state
		check_box.button_pressed = agent.world_state.get_state(state)
		check_box.toggled.connect(func(toggled_on: bool) -> void:
			agent.world_state.set_state(state, toggled_on))
		world_state_children.push_back(check_box)
		world_state_container.add_child(check_box)


func add_and_record(node: GoapBaseGraphNode) -> void:
	graph_nodes.push_back(node)
	graph_edit.add_child(node)
