@tool
extends VBoxContainer

var sessions: Dictionary = {}
var session_picker: OptionButton
var agent_picker: OptionButton
var pause_button: Button
var status: Label
var tabs: TabContainer
var plan_text: RichTextLabel
var goal_tree: Tree
var cost_tree: Tree
var action_tree: Tree
var timeline: ItemList
var event_text: RichTextLabel
var snapshot_text: RichTextLabel
var performance_view: VBoxContainer
var follow: CheckButton
var show_marker: CheckButton
var show_all_markers: CheckButton
var selection_note: Label
var selection_bar: HBoxContainer
var _session_id := -1
var _event_sequence := -1
var _decision_render_key := ""
var _shown_event_key := ""


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	session_picker = OptionButton.new()
	session_picker.item_selected.connect(func(index: int) -> void:
		_session_id = int(session_picker.get_item_metadata(index))
		refresh())
	bar.add_child(session_picker)
	agent_picker = OptionButton.new()
	agent_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agent_picker.item_selected.connect(func(index: int) -> void:
		var model: RefCounted = sessions.get(_session_id)
		if model != null:
			model.observe(int(agent_picker.get_item_metadata(index))))
	bar.add_child(agent_picker)
	pause_button = Button.new()
	pause_button.text = "Pause game"
	pause_button.tooltip_text = "Pause or resume the selected running game session."
	pause_button.pressed.connect(func() -> void:
		var model: RefCounted = sessions.get(_session_id)
		if model != null:
			model.set_paused(not model.paused))
	bar.add_child(pause_button)
	selection_bar = HBoxContainer.new()
	selection_bar.add_theme_constant_override("separation", 18)
	add_child(selection_bar)
	show_marker = CheckButton.new()
	show_marker.text = "Show marker in game"
	show_marker.tooltip_text = "Mark the observed Agent's 2D/3D owner with the same number as this list. Does not change game selection or handle input."
	show_marker.toggled.connect(func(enabled: bool) -> void:
		var model: RefCounted = sessions.get(_session_id)
		if model != null:
			model.set_marker_enabled(enabled))
	selection_bar.add_child(show_marker)
	show_all_markers = CheckButton.new()
	show_all_markers.text = "Show all markers"
	show_all_markers.tooltip_text = "Show every spatial Agent with its list identity. The observed Agent is cyan; other Agents are amber. No selection is required."
	show_all_markers.toggled.connect(func(enabled: bool) -> void:
		var model: RefCounted = sessions.get(_session_id)
		if model != null:
			model.set_all_markers_enabled(enabled))
	selection_bar.add_child(show_all_markers)
	selection_note = Label.new()
	selection_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(selection_note)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	plan_text = _text_panel("Plan & world state")
	tabs.add_child(plan_text)
	var decisions := VSplitContainer.new()
	decisions.name = "Decisions"
	tabs.add_child(decisions)
	var upper := HSplitContainer.new()
	decisions.add_child(upper)
	goal_tree = _tree(["Goal", "Priority", "Decision"])
	upper.add_child(goal_tree)
	action_tree = _tree(["Action", "Availability"])
	upper.add_child(action_tree)
	cost_tree = _tree(["Computed plans / actions", "Cost ↑", "Result"])
	decisions.add_child(cost_tree)
	var history := VBoxContainer.new()
	history.name = "Timeline"
	tabs.add_child(history)
	follow = CheckButton.new()
	follow.text = "Follow latest event"
	follow.button_pressed = true
	follow.toggled.connect(func(_value: bool) -> void: refresh())
	history.add_child(follow)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.add_child(split)
	timeline = ItemList.new()
	timeline.custom_minimum_size.x = 350
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.item_selected.connect(func(index: int) -> void:
		follow.set_pressed_no_signal(false)
		var event: Dictionary = timeline.get_item_metadata(index)
		_event_sequence = int(event.sequence)
		event_text.text = _event_details(event))
	split.add_child(timeline)
	event_text = _text_panel("Details")
	split.add_child(event_text)
	snapshot_text = _text_panel("Snapshot")
	tabs.add_child(snapshot_text)
	performance_view = preload("goap_performance_view.gd").new()
	performance_view.name = "Performance"
	tabs.add_child(performance_view)
	performance_view.reset_requested.connect(func() -> void:
		var model: RefCounted = sessions.get(_session_id)
		if model != null:
			model.reset_performance())
	tabs.current_tab = tabs.get_tab_idx_from_control(performance_view)
	tabs.tab_changed.connect(func(_index: int) -> void: refresh())
	refresh()


func add_session(id: int, model: RefCounted) -> void:
	if sessions.has(id):
		if sessions[id] == model:
			return
		sessions[id].changed.disconnect(refresh)
	sessions[id] = model
	model.changed.connect(refresh)
	_session_id = id
	if is_node_ready():
		refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	session_picker.clear()
	for id: int in sessions:
		session_picker.add_item("Session %d%s" % [id + 1, "" if sessions[id].connected else " · stopped"])
		session_picker.set_item_metadata(session_picker.item_count - 1, id)
		if id == _session_id:
			session_picker.select(session_picker.item_count - 1)
	var model: RefCounted = sessions.get(_session_id)
	pause_button.disabled = model == null or not model.connected
	pause_button.text = "Resume game" if model != null and model.paused else "Pause game"
	var showing_performance := tabs.get_current_tab_control() == performance_view
	agent_picker.visible = not showing_performance
	selection_bar.visible = not showing_performance
	selection_note.visible = not showing_performance
	show_marker.disabled = model == null or not model.connected
	show_all_markers.disabled = model == null or not model.connected
	show_marker.set_pressed_no_signal(model != null and model.marker_enabled)
	show_all_markers.set_pressed_no_signal(model != null and model.all_markers_enabled)
	selection_note.text = "Choose an Agent and enable Show marker in game to locate it."
	if model != null and model.marker_enabled and model.selected_id != 0:
		selection_note.text += " Marker uses the nearest 2D/3D owner; it is visible only when that owner is visible and on screen."
	if model != null and model.all_markers_enabled:
		selection_note.text = "All visible Agents are marked with their list identities. Cyan = observed; amber = other Agents."
	performance_view.display_snapshot(model.performance if model != null else {}, model != null and model.connected)
	_refresh_agent_picker(model)
	agent_picker.disabled = model == null or not model.connected
	if model == null or not model.connected:
		_decision_render_key = ""
		status.text = "Run the project from Godot (F5 / F6). Performance covers the whole session; select an Agent in the other tabs for decisions and execution history."
		plan_text.text = "No connected session."
		_clear_decisions()
		timeline.clear()
		event_text.clear()
		_shown_event_key = ""
		snapshot_text.clear()
		return
	status.text = "%d recent events · %d dropped before delivery. Decisions describe the last completed request; collection starts when you select an Agent." % [model.events.size(), model.dropped] if model.selected_id != 0 else "%d Agents. Select one to collect execution events and planning decisions." % model.agents.size()
	if showing_performance:
		status.text = "Performance · All Agents in the selected session · Updated every 0.1 seconds"
	_render_plan(model.snapshot)
	if tabs.current_tab == 3:
		snapshot_text.text = JSON.stringify(model.snapshot, "  ")
	var report: Dictionary = model.snapshot.get("statistics", {})
	var decisions: Dictionary = report.get("decisions", {})
	var decision_key := "%d:%d:%d:%s" % [_session_id, model.selected_id, int(report.get("generation", -1)), str(not decisions.is_empty())]
	if decision_key != _decision_render_key:
		_render_decisions(decisions)
		_decision_render_key = decision_key
	timeline.clear()
	var chosen := -1
	for event: Dictionary in model.events:
		var data: Dictionary = event.get("data", {})
		var label := "%d · %.3fs · %s" % [event.sequence, event.time_usec / 1000000.0, String(event.type).replace("_", " ")]
		if data.has("action"):
			label += " · " + String(data.action)
		timeline.add_item(label)
		timeline.set_item_metadata(timeline.item_count - 1, event)
		timeline.set_item_tooltip(timeline.item_count - 1, label)
		if int(event.sequence) == _event_sequence:
			chosen = timeline.item_count - 1
	if follow.button_pressed:
		chosen = timeline.item_count - 1
	if chosen >= 0:
		timeline.select(chosen)
		var event: Dictionary = timeline.get_item_metadata(chosen)
		_event_sequence = int(event.sequence)
		var event_key := "%d:%d:%d" % [_session_id, model.selected_id, _event_sequence]
		if event_key != _shown_event_key:
			event_text.text = _event_details(event)
			_shown_event_key = event_key
		if follow.button_pressed:
			timeline.ensure_current_is_visible()
	else:
		event_text.text = "Select an event. The timeline keeps the most recent 256 events; older events expire."
		_shown_event_key = ""


func _refresh_agent_picker(model: RefCounted) -> void:
	var entries: Array = model.agents if model != null and model.connected else []
	var rebuild := agent_picker.item_count != entries.size() + 1
	if not rebuild:
		for index in entries.size():
			var entry: Dictionary = entries[index]
			if agent_picker.get_item_metadata(index + 1) != int(entry.id) or agent_picker.get_item_text(index + 1) != String(entry.get("label", entry.path)):
				rebuild = true
				break
	if rebuild:
		agent_picker.clear()
		agent_picker.add_item("Select running Agent / stop observing")
		agent_picker.set_item_metadata(0, 0)
		for entry: Dictionary in entries:
			agent_picker.add_item(String(entry.get("label", entry.path)))
			var index := agent_picker.item_count - 1
			agent_picker.set_item_metadata(index, int(entry.id))
			agent_picker.set_item_tooltip(index, String(entry.path))
	var selected := 0
	if model != null:
		for index in entries.size():
			if int(entries[index].id) == model.selected_id:
				selected = index + 1
	if agent_picker.selected != selected:
		agent_picker.select(selected)
	if model != null and (model.marker_enabled or model.all_markers_enabled) and selected > 0 and not entries[selected - 1].get("can_mark", true):
		selection_note.text = "This Agent has no 2D/3D or Control owner to mark. Its full node path is available in the list tooltip and Plan & world state."


func _render_plan(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		plan_text.text = "Waiting for an observed Agent snapshot."
		return
	var lines := PackedStringArray([
		str(snapshot.get("label", "Observed Agent")),
		"Agent: " + str(snapshot.get("agent", "")),
		"Goal: " + str(snapshot.get("goal", "None")),
		"Generation: %s  ·  Planning: %s" % [snapshot.get("generation", 0), snapshot.get("is_planning", false)],
		"Plan cost: %s  ·  Search complete: %s" % [snapshot.get("cost", "—"), snapshot.get("search_complete", "—")],
		"", "Execution plan",
	])
	var actions: Array = snapshot.get("actions", [])
	var cost_labels: Array = snapshot.get("cost_labels", [])
	var step: int = snapshot.get("step", -1)
	for index in actions.size():
		var state := "done" if index < step else ("running" if index == step and snapshot.get("started", false) else "next")
		var cost_text := "  " + str(cost_labels[index]) if index < cost_labels.size() else ""
		lines.append("  %d. %s%s  [%s]" % [index + 1, actions[index], cost_text, state])
	if actions.is_empty():
		lines.append("  No active plan.")
	lines.append("\nWorld state")
	var world: Dictionary = snapshot.get("world", {})
	var keys := world.keys()
	keys.sort()
	for key in keys:
		lines.append("  %s = %s" % [key, str(world[key])])
	plan_text.text = "\n".join(lines)


func _render_decisions(decisions: Dictionary) -> void:
	_clear_decisions()
	var root := goal_tree.create_item()
	for goal: Dictionary in decisions.get("goals", []):
		var row := goal_tree.create_item(root)
		row.set_text(0, goal.id)
		row.set_text(1, str(goal.priority))
		row.set_text(2, _reason(goal.reason))
	if root.get_child_count() == 0:
		var row := goal_tree.create_item(root)
		row.set_text(0, "Await next completed request")
	root = action_tree.create_item()
	for action: Dictionary in decisions.get("actions", []):
		var row := action_tree.create_item(root)
		row.set_text(0, action.id)
		row.set_text(1, _reason(action.reason))
	root = cost_tree.create_item()
	for comparison: Dictionary in decisions.get("comparisons", []):
		var heading := cost_tree.create_item(root)
		heading.set_text(0, "%s · %d computed plan(s)%s" % [comparison.goal, comparison.candidate_count, " · search truncated" if not comparison.search_complete else ""])
		for candidate: Dictionary in _sorted_candidates(comparison.candidates):
			var row := cost_tree.create_item(heading)
			var label := " → ".join(candidate.actions)
			if candidate.steps > candidate.actions.size():
				label += " … (%d steps)" % candidate.steps
			row.set_text(0, label)
			row.set_tooltip_text(0, label)
			row.set_text(1, ("≥ " if candidate.cost_is_lower_bound else "") + str(candidate.cost))
			row.set_text(2, _reason(candidate.reason))


func _sorted_candidates(candidates: Array) -> Array:
	var sorted := candidates.duplicate()
	sorted.sort_custom(_candidate_cost_less)
	return sorted


func _candidate_cost_less(a: Dictionary, b: Dictionary) -> bool:
	var a_cost: Variant = a.get("cost")
	var b_cost: Variant = b.get("cost")
	if a_cost == null or b_cost == null:
		if a_cost == null and b_cost != null:
			return false
		if b_cost == null and a_cost != null:
			return true
	elif float(a_cost) != float(b_cost):
		return float(a_cost) < float(b_cost)
	var a_bound := bool(a.get("cost_is_lower_bound", false))
	var b_bound := bool(b.get("cost_is_lower_bound", false))
	if a_bound != b_bound:
		return not a_bound
	var a_selected: bool = a.get("reason", "") == "selected"
	var b_selected: bool = b.get("reason", "") == "selected"
	if a_selected != b_selected:
		return a_selected
	return int(a.get("index", 0)) < int(b.get("index", 0))


func _clear_decisions() -> void:
	goal_tree.clear()
	cost_tree.clear()
	action_tree.clear()


func _event_details(event: Dictionary) -> String:
	var lines := PackedStringArray(["%s · generation %s" % [_reason(event.type), event.generation]])
	var data: Dictionary = event.get("data", {})
	for key in data:
		if key == "report":
			var decisions: Dictionary = data.report.get("decisions", {})
			lines.append("\nGoal decisions")
			for goal: Dictionary in decisions.get("goals", []):
				lines.append("%s · Priority %s · %s" % [goal.id, str(goal.priority), _reason(goal.reason)])
			lines.append("\nRecorded planning report\n" + JSON.stringify(data.report, "  "))
		elif key == "changes":
			for change: Dictionary in data.changes:
				lines.append("%s: %s → %s" % [change.fact, str(change.before), str(change.after)])
		elif key == "step":
			lines.append("Step: %d" % (int(data[key]) + 1))
		else:
			lines.append("%s: %s" % [String(key).capitalize(), str(data[key])])
	return "\n".join(lines)


func _reason(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _text_panel(title: String) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.name = title
	text.selection_enabled = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return text


func _tree(titles: Array[String]) -> Tree:
	var tree := Tree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 180
	tree.columns = titles.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	for index in titles.size():
		tree.set_column_title(index, titles[index])
	return tree
