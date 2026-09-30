@tool
extends VSplitContainer

var agent_option_button := OptionButton.new()
var current_agent: GoapAgent
var current_plan: GoapPlan
var observed_world: GoapWorldState
var world_checks: Dictionary = {}
var live_status := Label.new()
var follow_current := CheckButton.new()
var _dirty := true
var _last_step := -1
var _last_running := false
var _layout_generation := 0

@onready var plan_browser = $Panel/Plan/PlanBrowser
@onready var inspector_tabs: TabContainer = $Panel/PanelContainer/MarginContainer/Tabs
@onready var world_state_container: VBoxContainer = $"Panel/PanelContainer/MarginContainer/Tabs/World facts/WorldStateContainer"
@onready var text_edit: TextEdit = $Panel2/TextEdit


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	plan_browser.inspector = $"Panel/PanelContainer/MarginContainer/Tabs/Details/Inspector"
	inspector_tabs.set_tab_title(1, "World state")
	plan_browser.step_inspected.connect(func() -> void: inspector_tabs.current_tab = 0)
	var menu: HBoxContainer = $Panel/Plan/Toolbar
	menu.add_child(agent_option_button)
	agent_option_button.item_selected.connect(
		func(index: int) -> void:
			inspect(instance_from_id(agent_option_button.get_item_metadata(index)))
	)
	follow_current.text = "Follow current"
	follow_current.button_pressed = true
	follow_current.toggled.connect(
		func(enabled: bool) -> void:
			if enabled:
				_focus_current()
	)
	menu.add_child(follow_current)
	var focus := Button.new()
	focus.text = "Current action"
	focus.pressed.connect(_focus_current)
	menu.add_child(focus)
	live_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	live_status.custom_minimum_size.x = 210
	if agent_option_button.item_count > 0:
		inspect(instance_from_id(agent_option_button.get_item_metadata(0)))
	else:
		build_world_state()
		build_tree()


func _process(_delta: float) -> void:
	# Action start/stop has no signal. Only update controls when runtime state changes.
	var step := current_plan.step if current_plan != null else -1
	var running := current_plan != null and current_plan._started
	if not _dirty and step == _last_step and running == _last_running:
		return
	var step_changed := step != _last_step
	_last_step = step
	_last_running = running
	_dirty = false
	_refresh_live_state()
	if step_changed and follow_current.button_pressed:
		_focus_current()


func add_agent(agent: GoapAgent) -> void:
	agent_option_button.add_item("%s#%d" % [agent.name, agent.get_instance_id()])
	agent_option_button.set_item_metadata(
		agent_option_button.item_count - 1,
		agent.get_instance_id()
	)
	if is_node_ready() and not is_instance_valid(current_agent):
		inspect(agent)


func remove_agent(agent: GoapAgent) -> void:
	for index in range(agent_option_button.item_count - 1, -1, -1):
		if agent_option_button.get_item_metadata(index) == agent.get_instance_id():
			agent_option_button.remove_item(index)
	if current_agent == agent:
		inspect(null)
		if agent_option_button.item_count > 0:
			agent_option_button.select(0)
			inspect(instance_from_id(agent_option_button.get_item_metadata(0)))


func inspect(agent: GoapAgent) -> void:
	if is_instance_valid(current_agent) and current_agent.plan_updated.is_connected(
		_on_plan_updated
	):
		current_agent.plan_updated.disconnect(_on_plan_updated)
	if observed_world != null and observed_world.state_changed.is_connected(_on_world_changed):
		observed_world.state_changed.disconnect(_on_world_changed)
	current_agent = agent
	observed_world = current_agent.world_state if is_instance_valid(current_agent) else null
	if observed_world != null:
		observed_world.state_changed.connect(_on_world_changed)
	if is_instance_valid(current_agent):
		current_agent.plan_updated.connect(_on_plan_updated)
	_on_plan_updated()
	if is_node_ready():
		build_world_state()
		if current_plan == null:
			build_tree()


func build_tree() -> void:
	_layout_generation += 1
	var goal: GoapGoal = current_agent.current_goal if is_instance_valid(current_agent) else null
	var cost_labels: Array = current_agent.get_plan_cost_labels(current_plan) if current_plan != null and current_agent.has_method("get_plan_cost_labels") else []
	plan_browser.set_live_plan(current_plan, goal, observed_world, cost_labels)
	_refresh_live_state()
	_focus_after_layout.call_deferred(_layout_generation)


func build_world_state() -> void:
	if live_status.get_parent() != null:
		live_status.get_parent().remove_child(live_status)
	for child in world_state_container.get_children():
		child.free()
	world_checks.clear()
	var heading := Label.new()
	heading.text = "LIVE EXECUTION"
	world_state_container.add_child(heading)
	world_state_container.add_child(live_status)
	world_state_container.add_child(HSeparator.new())
	heading = Label.new()
	heading.text = "World state"
	world_state_container.add_child(heading)
	if observed_world == null:
		live_status.text = "Select an agent to inspect its live state."
		return
	for key in observed_world.keys():
		var check := CheckBox.new()
		check.text = "%s = %s" % [key, str(observed_world.get_state(key))]
		check.tooltip_text = check.text
		check.set_pressed_no_signal(observed_world.get_state(key))
		check.button_mask = 0
		check.focus_mode = Control.FOCUS_NONE
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		check.clip_text = true
		check.tooltip_text = check.text
		world_checks[key] = check
		world_state_container.add_child(check)


func logger(message: String) -> void:
	if text_edit.get_line_count() > 1000:
		text_edit.remove_line_at(0)
	text_edit.insert_line_at(text_edit.get_line_count() - 1, message)


func _on_world_changed() -> void:
	_dirty = true


func _on_plan_updated() -> void:
	var next_plan: GoapPlan = current_agent.current_plan if is_instance_valid(
		current_agent
	) else null
	var changed := current_plan != next_plan
	if current_plan != null and current_plan.action_succeeded.is_connected(_on_action_succeeded):
		current_plan.action_succeeded.disconnect(_on_action_succeeded)
	current_plan = next_plan
	if current_plan != null:
		current_plan.action_succeeded.connect(_on_action_succeeded)
	_dirty = true
	if is_node_ready() and changed:
		_last_step = -1
		build_tree()
		if is_instance_valid(current_agent):
			logger("Planning: %s" % current_agent.planning_statistics)


func _on_action_succeeded(is_last_step: bool) -> void:
	logger("Action: %s succeeded" % current_plan.actions[current_plan.step].name)
	if is_last_step and current_agent.current_goal != null:
		logger("Goal: %s reached" % current_agent.current_goal.name)
	_dirty = true


func _focus_after_layout(generation: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_inside_tree() and generation == _layout_generation and follow_current.button_pressed:
		_focus_current()


func _focus_current() -> void:
	plan_browser.focus_current()


func _refresh_live_state() -> void:
	if observed_world == null:
		live_status.text = "Select an agent to inspect its live state."
		return
	var keys := observed_world.keys()
	if keys.size() != world_checks.size() or keys.any(
		func(key: StringName) -> bool: return not world_checks.has(key)
	):
		build_world_state()
	for key in keys:
		var check: CheckBox = world_checks[key]
		check.set_pressed_no_signal(observed_world.get_state(key))
		check.text = "%s = %s" % [key, str(observed_world.get_state(key))]
		check.tooltip_text = check.text
	if current_plan == null:
		live_status.text = "No active plan · Waiting for planning"
		return
	plan_browser.refresh_live()
	var finished := mini(current_plan.step, current_plan.actions.size())
	if finished == current_plan.actions.size():
		live_status.text = "Plan completed · %d / %d actions" % [finished, finished]
	else:
		live_status.text = "%s · %s\nStep %d / %d · %d completed" % [
			"Running" if current_plan._started else "Ready",
			current_plan.actions[finished].name,
			finished + 1,
			current_plan.actions.size(),
			finished
		]
