@tool
extends VBoxContainer

## Browse structural alternatives without expanding every search branch into a card.
signal step_inspected
signal preview_fact_changed(key: StringName, value: bool)
signal show_all_goals_changed

const ACCENT := Color("78bdec")
const MET := Color("8ec79b")
const MUTED := Color("a2adbd")
const NEEDED := Color("e3b776")

var groups: Array[Dictionary] = []
var selected_group := -1
var selected_plan_index := 0
var plan_routes: Array[Array] = []
var selected_step := 0
var inspector: VBoxContainer
var world: GoapWorldState
var fact_labels: Dictionary = {}
var heading: Label
var show_all_goals: CheckButton
var steps: VBoxContainer
var step_scroll: ScrollContainer
var step_buttons: Array[Button] = []
var displayed_actions: Array[GoapAction] = []
var plan_positions: Array[int] = []
var plan_lengths: Array[int] = []
var plan_numbers: Array[int] = []
var plan_summaries: Array[Dictionary] = []
var plan_buttons: Array[Button] = []
var plan_action_buttons: Array[Array] = []
var before_states: Array[GoapWorldState] = []
var sources: Array[Dictionary] = []
var current_sequence: Array = []
var live_plan: GoapPlan
var live_cost_labels: Array[String] = []
var live_goal: GoapGoal
var step_statuses: Array[Label] = []
var outcome: Label
var note: Label


static func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse(child)


static func _fact_summary(facts: GoapWorldState) -> String:
	var parts := PackedStringArray()
	for key in facts.keys():
		parts.append("%s = %s" % [key, str(facts.get_state(key))])
	return ", ".join(parts)


static func _missing_summary(required: GoapWorldState, actual: GoapWorldState) -> String:
	var parts := PackedStringArray()
	for key in required.keys():
		if actual.get_state(key) != required.get_state(key):
			parts.append("%s = %s (now %s)" % [
				key, str(required.get_state(key)), str(actual.get_state(key))
			])
	return ", ".join(parts)


func _fact_name(key: StringName) -> String:
	return str(fact_labels.get(key, key))


static func _label(text: String, font_size: int, color := Color("dce2ed")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func _card_style(background: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _ready() -> void:
	custom_minimum_size = Vector2(560, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	add_child(main)
	var header := HBoxContainer.new()
	main.add_child(header)
	heading = _label("Plans", 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(heading)
	show_all_goals = CheckButton.new()
	show_all_goals.text = "Show all"
	show_all_goals.tooltip_text = "Show plans for every goal."
	show_all_goals.toggled.connect(func(_enabled: bool) -> void: show_all_goals_changed.emit())
	header.add_child(show_all_goals)
	step_scroll = ScrollContainer.new()
	step_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(step_scroll)
	steps = VBoxContainer.new()
	steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps.add_theme_constant_override("separation", 16)
	step_scroll.add_child(steps)
	note = _label(
		"Plan preview · Select a plan for its actions. Dynamic cost and availability are evaluated at runtime.",
		12,
		MUTED
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(note)


func set_results(results: Array[Dictionary], initial: GoapWorldState, labels: Dictionary = {}) -> void:
	live_plan = null
	live_cost_labels.clear()
	live_goal = null
	fact_labels = labels
	show_all_goals.show()
	note.text = "Plan preview · Select a plan for its actions. Dynamic cost and availability are evaluated at runtime."
	var previous := str(groups[selected_group].key) if selected_group >= 0 else ""
	var previous_plan_goal := String((plan_summaries[selected_plan_index].goal as GoapGoal).get_id()) if selected_plan_index < plan_summaries.size() else ""
	var previous_action := String(displayed_actions[selected_step].get_id()) if selected_step >= 0 and selected_step < displayed_actions.size() else ""
	groups.clear()
	selected_group = -1
	world = initial
	var by_key: Dictionary = {}
	for result in results:
		var goal: GoapGoal = result.goal
		var priority := goal.get_priority(initial.duplicate())
		var actions: Array[GoapAction] = result.actions
		for candidate: Array in result.search.candidates:
			var sequence: Array[GoapAction] = []
			var ids: Array[String] = []
			for action_index: int in candidate:
				sequence.append(actions[action_index])
				ids.append(String(actions[action_index].get_id()))
			ids.sort()
			# Preserve multiplicity and goal identity for preview statistics.
			var key := JSON.stringify([goal.get_id(), ids])
			if not by_key.has(key):
				by_key[key] = groups.size()
				groups.append(
					{
						"key": key,
						"goal": goal,
						"priority": priority,
						"sequences": [],
						"steps": sequence.size()
					}
				)
			groups[by_key[key]].sequences.append(sequence)
		# An unreachable goal is still discoverable, with its unmet facts in the inspector.
		if result.search.candidates.is_empty():
			groups.append(
				{
					"key": String(goal.get_id()),
					"goal": goal,
					"priority": priority,
					"sequences": [],
					"steps": 2147483647,
					"search_complete": result.search.statistics.search_complete
				}
			)
	groups.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.priority != b.priority:
				return a.priority > b.priority
			if a.steps != b.steps:
				return a.steps < b.steps
			return a.key < b.key
	)
	if not groups.any(func(group: Dictionary) -> bool: return (group.goal as GoapGoal).get_id() == previous_plan_goal):
		selected_plan_index = 0
	_show_primary_route()
	if selected_group >= 0 and groups[selected_group].key == previous:
		for index in displayed_actions.size():
			if String(displayed_actions[index].get_id()) == previous_action:
				inspect_step(index)
				break


func clear() -> void:
	live_plan = null
	live_goal = null
	groups.clear()
	selected_group = -1
	selected_plan_index = 0
	world = null
	_show_primary_route()


func set_live_plan(plan: GoapPlan, goal: GoapGoal, state: GoapWorldState, cost_labels: Array = []) -> void:
	live_plan = plan
	live_cost_labels.assign(cost_labels)
	live_goal = goal
	fact_labels.clear()
	show_all_goals.hide()
	world = state
	groups.clear()
	selected_group = -1
	note.text = "Live execution · Select an action to inspect its conditions and effects."
	if plan == null or goal == null:
		_show_primary_route()
		heading.text = "No active plan"
		_add_message(
			"Waiting for planning." if state != null else "Select an agent to inspect its live state."
		)
		return
	groups.append(
		{
			"key": String(goal.get_id()),
			"goal": goal,
			"sequences": [plan.actions],
			"steps": plan.actions.size()
		}
	)
	_show_primary_route()
	refresh_live()


func refresh_live() -> void:
	if live_plan == null:
		return
	for index in step_buttons.size():
		var status := "Completed" if index < live_plan.step else "Running" if index == live_plan.step and live_plan._started else "Ready" if index == live_plan.step else "Pending"
		var color := MET if index < live_plan.step else ACCENT if index == live_plan.step else MUTED
		step_buttons[index].set_meta("execution_status", status)
		step_statuses[index].text = "ACTION %02d · %s" % [index + 1, status]
		step_statuses[index].add_theme_color_override("font_color", color)
		step_buttons[index].add_theme_stylebox_override(
			"normal",
			_card_style(Color("292e38"), color if index == live_plan.step else Color.TRANSPARENT)
		)
	if is_instance_valid(outcome):
		var reached := world.satisfies(live_goal.goal_state)
		outcome.text = "GOAL REACHED" if reached else "GOAL IN PROGRESS"
		outcome.add_theme_color_override("font_color", MET if reached else MUTED)
	if selected_step >= 0 and selected_step < step_buttons.size():
		inspect_step(selected_step)


func focus_current() -> void:
	if live_plan == null or step_buttons.is_empty():
		return
	var index := mini(live_plan.step, step_buttons.size() - 1)
	inspect_step(index)
	step_scroll.ensure_control_visible(step_buttons[index])


func focus_plan(index: int) -> void:
	if index < 0 or index >= plan_routes.size():
		return
	selected_plan_index = index
	for row in plan_buttons.size():
		plan_buttons[row].set_pressed_no_signal(row == index)
		for action_button: Button in plan_action_buttons[row]:
			action_button.set_pressed_no_signal(false)
	_inspect_plan(index)
	step_inspected.emit()


func focus_plan_step(plan_index: int, step_index: int) -> void:
	focus_plan(plan_index)
	inspect_step(step_index)
	step_inspected.emit()


func inspect_goal(goal: GoapGoal) -> void:
	if goal == null or world == null:
		return
	selected_step = -1
	for button in plan_buttons:
		button.set_pressed_no_signal(false)
	for row in plan_action_buttons:
		for action_button: Button in row:
			action_button.set_pressed_no_signal(false)
	_clear_inspector()
	_inspect_goal(goal)
	step_inspected.emit()


func _inspect_plan(index: int) -> void:
	_clear_inspector()
	selected_step = -1
	displayed_actions.clear()
	plan_positions.clear()
	plan_lengths.clear()
	plan_numbers.clear()
	before_states.clear()
	sources.clear()
	current_sequence = plan_routes[index]
	var summary: Dictionary = plan_summaries[index]
	var goal: GoapGoal = summary.goal
	_inspector_heading(String(goal.name), "Plan %02d · Base cost %.1f" % [index + 1, summary.base_cost])
	var facts := world.duplicate()
	var established_by: Dictionary = {}
	for step in current_sequence.size():
		var action: GoapAction = current_sequence[step]
		displayed_actions.append(action)
		plan_positions.append(step + 1)
		plan_lengths.append(current_sequence.size())
		plan_numbers.append(index + 1)
		before_states.append(facts.duplicate())
		sources.append(established_by.duplicate())
		facts.merge(action.effects, false)
		for key in action.effects.keys():
			established_by[key] = step
	if current_sequence.is_empty():
		inspector.add_child(_label("No actions are needed.", 13, MUTED))
	else:
		inspector.add_child(_label("Select an action in the plan to inspect its conditions.", 12, MUTED))
	inspector.add_child(HSeparator.new())
	inspector.add_child(_label("GOAL TARGET", 12, MUTED))
	_add_facts(goal.goal_state, world, {}, false)
	_add_goal_fact_controls(inspector, goal.goal_state)


func inspect_step(index: int) -> void:
	selected_step = index
	for button_index in step_buttons.size():
		step_buttons[button_index].set_pressed_no_signal(button_index == index)
	for row_index in plan_action_buttons.size():
		for button_index in plan_action_buttons[row_index].size():
			var action_button: Button = plan_action_buttons[row_index][button_index]
			action_button.set_pressed_no_signal(row_index == selected_plan_index and button_index == index)
	_clear_inspector()
	var action: GoapAction = displayed_actions[index]
	if live_plan != null:
		_inspect_live_step(index, action)
		return
	var back := Button.new()
	back.text = "Back to plan"
	back.pressed.connect(_inspect_plan.bind(selected_plan_index))
	inspector.add_child(back)
	_inspector_heading(
		String(action.name),
		"Plan %02d · action %02d of %02d · Preview" % [plan_numbers[index], plan_positions[index], plan_lengths[index]]
	)
	inspector.add_child(_label("PRECONDITIONS", 12, MUTED))
	if action.preconditions.size() == 0:
		inspector.add_child(_label("No prerequisites", 13, MET))
	_add_facts(action.preconditions, before_states[index], sources[index])
	inspector.add_child(HSeparator.new())
	inspector.add_child(_label("STATE CHANGES · BEFORE → AFTER", 12, MUTED))
	for key in action.effects.keys():
		var before: Variant = before_states[index].get_state(key)
		var value := _label(
			"%s\n%s → %s" % [
				key,
				str(before),
				str(action.effects.get_state(key))
			],
			13
		)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspector.add_child(value)
	var script := GoapTheme.definition_script(action)
	if not Engine.is_editor_hint() or script == null:
		return
	var open_script := Button.new()
	open_script.text = "Open action script"
	open_script.pressed.connect(
		func() -> void:
			# The same browser also ships in runtime builds, where this class is absent.
			var editor := Engine.get_singleton("EditorInterface")
			editor.call("edit_script", script)
			editor.call("set_main_screen_editor", "Script")
	)
	inspector.add_child(open_script)


func _show_primary_route() -> void:
	selected_group = 0 if not groups.is_empty() else -1
	selected_step = -1
	if selected_group < 0:
		_clear_steps()
		_clear_inspector()
		heading.text = "Select an agent to explore plans"
		return
	_show_sequence()


func _show_sequence() -> void:
	_clear_steps()
	_clear_inspector()
	var goal: GoapGoal = groups[selected_group].goal
	heading.text = "Plans" if live_plan == null else String(goal.name).to_snake_case().capitalize()
	var goal_missing := _missing_summary(goal.goal_state, world)
	for group in groups:
		for sequence: Array in group.sequences:
			plan_routes.append(sequence)
			var names := PackedStringArray()
			var base_cost := 0.0
			if sequence.is_empty():
				names.append("Already satisfied")
			for action: GoapAction in sequence:
				names.append(String(action.name).to_snake_case().capitalize())
				base_cost += action.cost
			plan_summaries.append({
				"number": plan_routes.size(), "goal": group.goal, "actions": names,
				"base_cost": base_cost
			})
	var plan_count := plan_routes.size()
	if plan_count == 0:
		selected_plan_index = 0
		var message := "No complete plan from these facts." if groups[selected_group].search_complete else "Search limit reached; no complete plan found yet."
		_add_message(message + "\nGoal target: " + goal_missing + "\nChange World state to reveal available plans.")
		_inspect_goal(goal)
		return
	selected_plan_index = mini(selected_plan_index, plan_count - 1)
	if live_plan == null:
		heading.text = "%s  ·  %d plans" % [
			"All goals" if show_all_goals.button_pressed else String(goal.name).to_snake_case().capitalize(),
			plan_count
		]
		steps.add_theme_constant_override("separation", 6)
		var previous_goal: GoapGoal = null
		for index in plan_summaries.size():
			var summary: Dictionary = plan_summaries[index]
			var row_goal: GoapGoal = summary.goal
			if show_all_goals.button_pressed and row_goal != previous_goal:
				var group_count := 0
				for candidate in plan_summaries:
					if candidate.goal == row_goal:
						group_count += 1
				var group_label := _label("%s  ·  Priority %.1f  ·  %d plan(s)" % [
					String(row_goal.name).to_snake_case().capitalize(),
					row_goal.get_priority(world.duplicate()), group_count
				], 14, MET)
				group_label.custom_minimum_size.y = 28
				steps.add_child(group_label)
				previous_goal = row_goal
			var sequence: Array = plan_routes[index]
			var chain: PackedStringArray = summary.actions
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", _card_style(Color("30343b")))
			steps.add_child(card)
			var contents := VBoxContainer.new()
			contents.add_theme_constant_override("separation", 7)
			card.add_child(contents)
			var button := Button.new()
			button.toggle_mode = true
			button.flat = true
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.text = "PLAN %02d  ·  %d steps  ·  Cost %.1f" % [
				summary.number, sequence.size(), summary.base_cost
			]
			button.add_theme_color_override("font_color", ACCENT)
			button.tooltip_text = "%s\n%s\nBase cost: %.1f (runtime cost models may differ)." % [
				String(row_goal.name).to_snake_case().capitalize(), " → ".join(chain), summary.base_cost
			]
			button.pressed.connect(focus_plan.bind(index))
			contents.add_child(button)
			plan_buttons.append(button)
			var action_buttons: Array[Button] = []
			if sequence.is_empty():
				contents.add_child(_label("Already satisfied · no actions needed", 13, MET))
			else:
				var action_row := HFlowContainer.new()
				action_row.add_theme_constant_override("h_separation", 6)
				action_row.add_theme_constant_override("v_separation", 6)
				contents.add_child(action_row)
				for step in sequence.size():
					var action: GoapAction = sequence[step]
					var action_button := Button.new()
					action_button.toggle_mode = true
					action_button.text = "%02d  %s" % [
						step + 1, String(action.name).to_snake_case().capitalize()
					]
					action_button.tooltip_text = "Requires: %s\nProduces: %s" % [
						_fact_summary(action.preconditions), _fact_summary(action.effects)
					]
					action_button.add_theme_stylebox_override("normal", _card_style(Color("242a33")))
					action_button.add_theme_stylebox_override("hover", _card_style(Color("344357")))
					action_button.add_theme_stylebox_override("pressed", _card_style(Color("344357"), ACCENT))
					action_button.pressed.connect(focus_plan_step.bind(index, step))
					action_row.add_child(action_button)
					action_buttons.append(action_button)
			plan_action_buttons.append(action_buttons)
		for group in groups:
			if group.sequences.is_empty():
				steps.add_child(_label("%s · No complete plan" % String((group.goal as GoapGoal).name).to_snake_case().capitalize(), 13, MUTED))
		focus_plan(selected_plan_index)
		step_scroll.scroll_vertical = 0
		return
	current_sequence = plan_routes[selected_plan_index]
	heading.text += "  ·  %d steps" % current_sequence.size()
	steps.add_theme_constant_override("separation", 16)
	_add_plan_sequence(current_sequence, selected_plan_index + 1)
	_add_state_band(
		"GOAL SATISFIED" if goal_missing.is_empty() else "GOAL ACTIVE · TARGET NEEDS %d FACT(S)" % goal.goal_state.difference(world).size(),
		_fact_summary(goal.goal_state) if goal_missing.is_empty() else goal_missing,
		MET
	)
	selected_step = -1
	_inspect_goal(goal)
	step_scroll.scroll_vertical = 0


func _add_plan_sequence(sequence: Array, plan_number: int) -> void:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)
	steps.add_child(section)
	var plan_name := "Already satisfied" if sequence.is_empty() else String(sequence.back().name).to_snake_case().capitalize()
	var plan_title := "PLAN %02d · %s · %d steps" % [plan_number, plan_name, sequence.size()]
	if live_plan != null:
		plan_title += " · Cost %.2f" % live_plan.cost
	section.add_child(_label(plan_title, 14, ACCENT))
	if sequence.is_empty():
		section.add_child(_label("No actions are needed.", 13, MUTED))
		return
	var facts := world.duplicate()
	var established_by: Dictionary = {}
	var plan_route := VBoxContainer.new()
	plan_route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plan_route.add_theme_constant_override("separation", 8)
	section.add_child(plan_route)
	for index in sequence.size():
		var action: GoapAction = sequence[index]
		var global_index := displayed_actions.size()
		displayed_actions.append(action)
		plan_positions.append(index + 1)
		plan_lengths.append(sequence.size())
		plan_numbers.append(plan_number)
		before_states.append(facts.duplicate())
		sources.append(established_by.duplicate())
		var button := Button.new()
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(160, 88)
		button.tooltip_text = "%s\nProduces: %s\nSelect to inspect prerequisites and their sources." % [
			action.name,
			_fact_summary(action.effects)
		]
		button.add_theme_stylebox_override("normal", _card_style(Color("292e38")))
		button.add_theme_stylebox_override("hover", _card_style(Color("343f50")))
		button.add_theme_stylebox_override("pressed", _card_style(Color("292e38"), ACCENT))
		button.add_theme_stylebox_override("focus", _card_style(Color.TRANSPARENT, ACCENT))
		button.pressed.connect(func() -> void: inspect_step(global_index); step_inspected.emit())
		plan_route.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		button.add_child(margin)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.alignment = BoxContainer.ALIGNMENT_CENTER
		copy.add_theme_constant_override("separation", 5)
		margin.add_child(copy)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 16)
		copy.add_child(header)
		var status := _label("ACTION %02d" % [index + 1], 12, ACCENT)
		header.add_child(status)
		step_statuses.append(status)
		var title := _label(String(action.name).to_snake_case().capitalize(), 18)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.max_lines_visible = 2
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		header.add_child(title)
		if live_plan != null and index < live_cost_labels.size() and not live_cost_labels[index].is_empty():
			copy.add_child(_label(live_cost_labels[index], 13, ACCENT))
		var effects := _label(_fact_summary(action.effects), 12, MUTED)
		effects.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		effects.clip_text = true
		effects.tooltip_text = effects.text
		copy.add_child(effects)
		var missing_now := _missing_summary(action.preconditions, world)
		var missing_before := _missing_summary(action.preconditions, facts)
		var requirements := _label(
			"Ready now" if missing_now.is_empty() else "Now needs: " + missing_now,
			12,
			MET if missing_now.is_empty() else NEEDED
		)
		requirements.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		requirements.clip_text = true
		requirements.tooltip_text = requirements.text
		copy.add_child(requirements)
		if not missing_before.is_empty():
			var warning := _label("Before this step needs: " + missing_before, 12, NEEDED)
			warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			copy.add_child(warning)
		# Editor font scaling can make the text taller than the runtime theme.
		margin.minimum_size_changed.connect(
			func() -> void:
				button.custom_minimum_size.y = maxf(88, margin.get_combined_minimum_size().y)
		)
		button.custom_minimum_size.y = maxf(88, margin.get_combined_minimum_size().y)
		_ignore_mouse(margin)
		step_buttons.append(button)
		facts.merge(action.effects, false)
		for key in action.effects.keys():
			established_by[key] = global_index


func _add_goal_fact_controls(parent: Control, required: GoapWorldState) -> void:
	if required.size() == 0:
		parent.add_child(_label("This goal has no state conditions to change.", 12, MUTED))
		return
	for key in required.keys():
		var choice := CheckBox.new()
		choice.text = _fact_name(key)
		choice.set_meta("fact", key)
		choice.set_pressed_no_signal(world.get_state(key))
		choice.tooltip_text = "Goal target: %s = %s. Toggle the preview world fact." % [key, str(required.get_state(key))]
		choice.toggled.connect(func(value: bool) -> void: preview_fact_changed.emit(key, value))
		parent.add_child(choice)


func _inspect_goal(goal: GoapGoal) -> void:
	_inspector_heading(String(goal.name), "Active" if not world.satisfies(goal.goal_state) else "Satisfied")
	inspector.add_child(_label("ACTIVATE GOAL IN PREVIEW", 12, MET))
	var hint := _label(
		"This goal has no state conditions to change." if goal.goal_state.size() == 0 else "Check a fact to set it true; uncheck it to set it false.",
		12, MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(hint)
	if live_plan == null and goal.goal_state.size() > 0:
		_add_goal_fact_controls(inspector, goal.goal_state)
	inspector.add_child(HSeparator.new())
	inspector.add_child(_label("GOAL TARGET (AFTER PLAN)", 12, MUTED))
	_add_facts(goal.goal_state, world, {}, false)


func _add_state_band(title: String, summary: String, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style(Color("252a31"), color))
	steps.add_child(panel)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 6)
	panel.add_child(copy)
	outcome = _label(title, 11, color)
	copy.add_child(outcome)
	var label := _label(summary if not summary.is_empty() else "No known prerequisites", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = label.text
	copy.add_child(label)
	return copy


func _inspect_live_step(index: int, action: GoapAction) -> void:
	var completed := index < live_plan.step
	_inspector_heading(
		String(action.name),
		"Step %02d of %02d - %s%s" % [
			index + 1,
			current_sequence.size(),
			step_buttons[index].get_meta("execution_status", "Pending"),
			" · " + live_cost_labels[index] if index < live_cost_labels.size() else ""
		]
	)
	inspector.add_child(_label("PRECONDITIONS - LIVE WORLD", 12, MUTED))
	if action.preconditions.size() == 0:
		inspector.add_child(_label("No prerequisites", 13, MET))
	if completed:
		var hint := _label(
			"Completed action. These conditions are no longer required; values below reflect the live world.",
			13,
			MUTED
		)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspector.add_child(hint)
	_add_facts(action.preconditions, world)
	inspector.add_child(HSeparator.new())
	inspector.add_child(_label("ACTION EFFECTS", 12, MUTED))
	_add_facts(action.effects)


func _add_facts(
	facts: GoapWorldState,
	before: GoapWorldState = null,
	origins: Dictionary = {},
	allow_preview_edit := true
) -> void:
	for key in facts.keys():
		var row := VBoxContainer.new()
		row.set_meta("fact", key)
		row.set_meta("value", facts.get_state(key))
		var value := _label("%s = %s" % [_fact_name(key), str(facts.get_state(key))], 13)
		value.tooltip_text = String(key)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(value)
		if before != null:
			var met: bool = before.get_state(key) == facts.get_state(key)
			row.set_meta("satisfied", met)
			var source := "Met · World state" if met else "Needed · Current: %s" % str(
				before.get_state(key)
			)
			if met and origins.has(key):
				var origin: int = origins[key]
				var link := Button.new()
				link.flat = true
				link.alignment = HORIZONTAL_ALIGNMENT_LEFT
				link.set_meta("source_step", origin)
				link.text = "Met · Step %02d / %s" % [plan_positions[origin], displayed_actions[origin].name]
				link.add_theme_color_override("font_color", ACCENT)
				link.add_theme_font_size_override("font_size", 12)
				link.clip_text = true
				link.tooltip_text = link.text
				link.pressed.connect(
					func() -> void:
						inspect_step(origin)
						if origin < step_buttons.size():
							step_scroll.ensure_control_visible(step_buttons[origin])
				)
				row.add_child(link)
			else:
				row.add_child(_label(source, 12, MET if met else NEEDED))
			if allow_preview_edit and live_plan == null and world != null:
				var choice := CheckBox.new()
				choice.text = "World state · %s" % _fact_name(key)
				choice.set_meta("fact", key)
				choice.set_pressed_no_signal(world.get_state(key))
				choice.tooltip_text = "%s · Toggle the starting world fact. Earlier actions may also satisfy this requirement." % key
				choice.toggled.connect(func(enabled: bool) -> void:
					preview_fact_changed.emit(key, enabled))
				row.add_child(choice)
		inspector.add_child(row)


func _inspector_heading(title: String, subtitle: String) -> void:
	var label := _label(title, 18, ACCENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(label)
	label = _label(subtitle, 12, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(label)
	inspector.add_child(HSeparator.new())


func _clear_steps() -> void:
	outcome = null
	selected_step = -1
	step_statuses.clear()
	for child in steps.get_children():
		steps.remove_child(child)
		child.queue_free()
	step_buttons.clear()
	plan_buttons.clear()
	plan_action_buttons.clear()
	plan_routes.clear()
	plan_summaries.clear()
	displayed_actions.clear()
	plan_positions.clear()
	plan_lengths.clear()
	plan_numbers.clear()
	before_states.clear()
	sources.clear()
	current_sequence = []


func _clear_inspector() -> void:
	if inspector == null:
		return
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()


func _add_message(message: String) -> void:
	var label := _label(message, 14, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps.add_child(label)
