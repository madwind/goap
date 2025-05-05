@tool
extends VSplitContainer
var edit_children: Array[GoapBaseGraphNode]
var world_state_children: Array[CheckBox]
var agent_option_button := OptionButton.new()
var current_agent: GoapAgent
var current_plan: GoapPlan
var current_goal: GoapGoal
var current_world_state: GoapWorldState

@onready var graph_edit: GraphEdit = $Panel/GraphEdit
@onready var world_state_container: VBoxContainer = $Panel/PanelContainer/MarginContainer/WorldStateContainer
@onready var text_edit: TextEdit = $Panel2/TextEdit


func _ready() -> void:
	if not Engine.is_editor_hint():
		var menu_hbox := graph_edit.get_menu_hbox()
		agent_option_button.item_selected.connect(_on_item_selected)
		menu_hbox.add_child(agent_option_button)
		if not current_agent and agent_option_button.get_selected_metadata():
			inspect(agent_option_button.get_selected_metadata())
			await get_tree().process_frame
			graph_edit.scroll_offset -= Vector2(100, 100)


func _on_item_selected(index: int) -> void:
	inspect(agent_option_button.get_selected_metadata())


func add_agent(agent: GoapAgent):
	var label = "%s#%d" % [agent.actor.name, agent.get_instance_id()]
	agent_option_button.add_item(label, agent.get_instance_id())
	agent_option_button.set_item_metadata(agent_option_button.get_item_index(agent.get_instance_id()), agent)


func remove_agent(agent: GoapAgent):
	agent_option_button.remove_item(agent.get_instance_id())


func inspect(agent: GoapAgent):
	if current_agent:
		current_agent.plan_updated.disconnect(_on_plan_updated)
	current_agent = agent
	current_agent.plan_updated.connect(_on_plan_updated)
	build_tree()
	build_world_state()


func _on_plan_updated() -> void:
	if current_agent._current_plan:
		if current_plan:
			current_plan.action_succeed.disconnect(_on_action_succeed)
		current_plan = current_agent._current_plan
		current_plan.action_succeed.connect(_on_action_succeed)
	current_world_state = current_agent.world_state.duplicate()
	build_tree()
	build_world_state()


func _on_action_succeed(completed: bool) -> void:
	var action = current_plan.actions[current_plan.step]
	logger("Action: %s succeed" % action.name)
	var index := edit_children.find_custom(func(node: GoapBaseGraphNode) -> bool: return node.title == action.name)
	if index != -1:
		edit_children[index].set_color(GoapTheme.COLOR_SUCCESS)
	if not completed:
		current_world_state.merge(action.effects)
		build_world_state()
		var next_action = current_plan.actions[current_plan.step + 1]
		var next_index := edit_children.find_custom(func(node: GoapBaseGraphNode) -> bool: return node.title == next_action.name)
		if next_index != -1:
			edit_children[next_index].set_color(GoapTheme.COLOR_RUNNING)
	else:
		logger("Goal: %s succeed" % current_goal.name)


func build_tree() -> void:
	for child in edit_children:
		graph_edit.remove_child(child)
	edit_children.clear()
	if current_plan:
		extra_plan(current_plan.plan_node)
	graph_edit.arrange_nodes()


func extra_plan(plan_node: GoapPlanNode, next_node: GoapBaseGraphNode = null):
	if plan_node.goal:
		current_goal = plan_node.goal
		logger("New plan: Goal: %s, Actions: %s, Planning Time(ms): %d" % [current_goal.name, str(current_plan.actions), current_plan.planning_time_ms])
		var goal_graph_node := GoapGoalGraphNode.new(current_goal)
		goal_graph_node.set_color(GoapTheme.COLOR_ACTIVE)
		add_and_record(goal_graph_node)
		if next_node:
			graph_edit.connect_node(goal_graph_node.name, 0, next_node.name, 0)
		return
	var action_node := GoapActionGraphNode.new(plan_node.action, plan_node.unmet_goals)
	action_node.set_color(GoapTheme.COLOR_PENDING)
	add_and_record(action_node)
	if next_node:
		graph_edit.connect_node(action_node.name, 0, next_node.name, 0)
	else:
		action_node.set_color(GoapTheme.COLOR_RUNNING)
		if action_node.get_output_port_count() > 0:
			action_node.set_slot_enabled_right(action_node.get_output_port_slot(0), false)
	if plan_node.parent:
		extra_plan(plan_node.parent, action_node)


func build_world_state() -> void:
	for node in world_state_children:
		world_state_container.remove_child(node)
	world_state_children.clear()
	if current_world_state:
		for state in current_world_state.keys():
			var check_box := CheckBox.new()
			check_box.text = state
			check_box.button_pressed = current_world_state.get_state(state)
			check_box.button_mask = 0
			world_state_children.push_back(check_box)
			world_state_container.add_child(check_box)


func add_and_record(node: GoapBaseGraphNode) -> void:
	edit_children.push_back(node)
	graph_edit.add_child(node)


func logger(text: String) -> void:
	if text_edit.get_line_count() > 9999:
		text_edit.remove_line_at(0)
	text_edit.insert_line_at(text_edit.get_line_count() - 1, text)
