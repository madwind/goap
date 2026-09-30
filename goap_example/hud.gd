extends "res://addons/goap/runtime/goap_runtime_monitor.gd"
## In-game sidebar: agent details and workload controls.

@onready var count_input: SpinBox = $RuntimeWindow/RuntimePanel/Column/Tabs/Performance/Performance/Column/Body/Settings/Population/Count
@onready var agent_panel: ScrollContainer = $RuntimeWindow/RuntimePanel/Column/Tabs/Agent
@onready var agent_title: Label = $RuntimeWindow/RuntimePanel/Column/Tabs/Agent/Sidebar/Column/Title
@onready var selection_input: SpinBox = $RuntimeWindow/RuntimePanel/Column/Tabs/Agent/Sidebar/Column/Selection/Index
@onready var stats: GridContainer = $RuntimeWindow/RuntimePanel/Column/Tabs/Agent/Sidebar/Column/Body/Overview/Stats
@onready var goal_list: VBoxContainer = $RuntimeWindow/RuntimePanel/Column/Tabs/Agent/Sidebar/Column/Body/Execution/Planning/GoalsColumn/GoalList
@onready var steps_label: RichTextLabel = $RuntimeWindow/RuntimePanel/Column/Tabs/Agent/Sidebar/Column/Body/Execution/Planning/PlanColumn/Steps
@onready var pause_button: Button = $Root/Toolbar/Pause
@onready var overhead_vitals: PanelContainer = $Root/OverheadVitals
@onready var world_health_bars: Control = $Root/WorldHealthBars
@onready var toolbar_hint: Label = $Root/Toolbar/Hint
var _world: Node3D
var _paused_by_hud := false
var _goal_rows: PackedStringArray = []
var _carrying_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	super._ready()
	page_titles[1] = "Workload"
	tabs.set_tab_title(tabs.get_tab_idx_from_control(pages[1]), "Workload")
	tabs.drag_to_rearrange_enabled = false
	panel.get_node("Column/Header").hide()
	panel.reparent($Root, false)
	var sidebar_style := StyleBoxFlat.new()
	sidebar_style.bg_color = Color("101920")
	sidebar_style.border_width_left = 2
	sidebar_style.border_color = Color("507b75")
	sidebar_style.content_margin_left = 12.0
	sidebar_style.content_margin_right = 12.0
	sidebar_style.content_margin_top = 12.0
	sidebar_style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", sidebar_style)
	window.queue_free()
	for key in ["Raw", "Cooked", "Wood", "Water", "Stone"]:
		stats.get_node(key).hide()
		stats.get_node(key + "Label").hide()
	stats.get_parent().get_node("Heading").text = "VITALS & GEAR"
	_carrying_label = Label.new()
	_carrying_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_carrying_label.add_theme_font_size_override("font_size", 14)
	_carrying_label.add_theme_color_override("font_color", Color("80d9c4"))
	stats.get_parent().add_child(_carrying_label)
	pause_button.pressed.connect(_toggle_simulation_pause)
	get_viewport().size_changed.connect(_layout_split)
	_layout_split()


func _exit_tree() -> void:
	if _paused_by_hud:
		get_tree().paused = false
	super._exit_tree()


func _toggle_simulation_pause() -> void:
	_paused_by_hud = not get_tree().paused
	get_tree().paused = _paused_by_hud
	pause_button.text = "Resume" if get_tree().paused else "Pause"
	if is_instance_valid(_world):
		update_world(_world)


func _layout_split() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	var sidebar_width := minf(500.0, maxf(360.0, viewport_width * 0.36))
	sidebar_width = minf(sidebar_width, maxf(160.0, viewport_width - 160.0))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -sidebar_width
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	toolbar_hint.visible = viewport_width - sidebar_width >= 720.0


func map_width() -> float:
	return maxf(1.0, get_viewport().get_visible_rect().size.x - (panel.size.x if panel.visible else 0.0))


func show_monitor() -> void:
	if panel.visible:
		return
	panel.show()
	if is_instance_valid(_world):
		_world._fit_map_to_screen()


func hide_monitor() -> void:
	if not panel.visible:
		return
	panel.hide()
	if is_instance_valid(_world):
		_world._fit_map_to_screen()


func show_tab(index: int) -> void:
	if index < 0 or index >= pages.size():
		return
	show_monitor()
	tabs.current_tab = tabs.get_tab_idx_from_control(pages[index])


func detach_tab(_index: int) -> void:
	pass


func dock_tab(_index: int) -> void:
	pass


func update_world(world: Node3D) -> void:
	pause_button.text = "Resume" if get_tree().paused else "Pause"
	var actor: Node3D = world.actors[world.selected_index]
	var agent := actor.get_node("GoapAgent") as GoapAgent
	_update_goal_list(agent)
	if agent.current_plan == null or agent.current_plan.actions.is_empty():
		steps_label.text = "[color=#e6effa]No plan[/color]"
	else:
		var steps: PackedStringArray = []
		for index in agent.current_plan.actions.size():
			var title := "%d. %s" % [index + 1, agent.current_plan.actions[index].name]
			if index < agent.current_plan.step:
				steps.append("[color=#89a2b3][s]%s[/s][/color]" % title)
			elif index == agent.current_plan.step:
				steps.append("[color=#80d9c4][u]%s[/u][/color]" % title)
			else:
				steps.append("[color=#e6effa]%s[/color]" % title)
		steps_label.text = "\n".join(steps)
	stats.get_node("Satiety").text = "%d/100" % ceili(actor.satiety)
	stats.get_node("Hydration").text = "%d/100" % ceili(actor.hydration)
	stats.get_node("Health").text = "%d/20 HP" % actor.health
	var carried: PackedStringArray = actor.carried_items()
	_carrying_label.text = "Carrying: %s" % (", ".join(carried) if not carried.is_empty() else "nothing")
	stats.get_node("Weapon").text = "%d/10" % actor.weapon_durability
	stats.get_node("Meals").text = str(actor.meals)
	stats.get_node("State").text = "Dead" if actor.dead else (
		"Dehydrated" if actor.is_dehydrated() else ("Starving" if actor.is_starving() else (
			"Recovering" if actor.is_low_health() else ("Alert" if actor.get_threat() != null else "Safe")
		))
	)
	toolbar_hint.text = "Agents carry supplies to the fenced camp"


func _update_goal_list(agent: GoapAgent) -> void:
	var ranked: Array[GoapGoal] = agent.goals.duplicate()
	ranked.sort_custom(func(a: GoapGoal, b: GoapGoal) -> bool:
		if a == b:
			return false
		if a == agent.current_goal:
			return true
		if b == agent.current_goal:
			return false
		var a_priority := agent.goal_priority(a, agent.world_state)
		var b_priority := agent.goal_priority(b, agent.world_state)
		return a_priority > b_priority if a_priority != b_priority else a.name < b.name
	)
	var rows := PackedStringArray()
	for goal in ranked:
		var priority := agent.goal_priority(goal, agent.world_state)
		var priority_text := str(int(priority)) if is_equal_approx(priority, roundf(priority)) else str(priority)
		rows.append("%s\t%s\t%s" % ["current" if goal == agent.current_goal else "", goal.name, priority_text])
	if rows == _goal_rows:
		return
	_goal_rows = rows
	for child in goal_list.get_children():
		goal_list.remove_child(child)
		child.queue_free()
	if ranked.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No goals"
		goal_list.add_child(empty_label)
		return
	for goal_index in ranked.size():
		var goal := ranked[goal_index]
		var current := goal == agent.current_goal
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 6)
		goal_list.add_child(entry)
		var marker := ColorRect.new()
		marker.custom_minimum_size = Vector2(3, 0)
		marker.color = Color("80d9c4") if current else Color.TRANSPARENT
		entry.add_child(marker)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 1)
		entry.add_child(details)
		var name_label := Label.new()
		name_label.text = goal.name
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color("80d9c4") if current else Color("e6effa"))
		details.add_child(name_label)
		var priority_label := Label.new()
		priority_label.text = "Priority " + rows[goal_index].get_slice("\t", 2)
		priority_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		priority_label.add_theme_font_size_override("font_size", 12)
		priority_label.add_theme_color_override("font_color", Color("89a2b3"))
		details.add_child(priority_label)


## Called after the world and all HUD children are ready. UI paths stay here.
func bind_world(world: Node3D) -> void:
	_world = world
	overhead_vitals.world = world
	world_health_bars.world = world
	selection_input.value_changed.connect(world.select_agent)
	count_input.get_parent().get_node("Apply").pressed.connect(apply_population.bind(world))
	performance.get_node("Body/Settings/Actions/Replan").pressed.connect(world.replan_all)
	performance.get_node("Body/Settings/Actions/Clear").pressed.connect(world.reset_performance)
	performance.get_node(
		"Body/Settings/StressMode"
	).button_pressed = not world.stress.config.is_empty()
	for field in ["goals", "steps", "alternatives", "limit"]:
		if world.stress.config.has(field):
			performance.get_node("Body/Settings/Complexity/" + field).value = world.stress.config[
				field
			]


func apply_population(world: Node3D) -> void:
	# Commit typed numbers even while a SpinBox still has keyboard focus.
	count_input.apply()
	var config: Dictionary = {}
	if performance.get_node("Body/Settings/StressMode").button_pressed:
		for field in ["goals", "steps", "alternatives", "limit"]:
			var input: SpinBox = performance.get_node("Body/Settings/Complexity/" + field)
			input.apply()
			config[field] = int(input.value)
	world.apply_population(int(count_input.value), config)
	count_input.get_line_edit().release_focus()


func set_population(count: int) -> void:
	count_input.value = count
	selection_input.max_value = count


func select_agent(index: int) -> void:
	selection_input.set_value_no_signal(index + 1)
	agent_title.text = "Agent #%d" % (index + 1)



