extends RefCounted
## Human-readable view of the planner's bounded decision report for this example.


static func matches_current_plan(agent: GoapAgent, report: Dictionary) -> bool:
	if agent.current_plan == null or agent.current_goal == null:
		return false
	var full_ids: Array[String] = []
	var remaining_ids: Array[String] = []
	for index in agent.current_plan.actions.size():
		var id := agent.current_plan.actions[index].get_id()
		full_ids.append(id)
		if index >= agent.current_plan.step:
			remaining_ids.append(id)
	for group: Dictionary in report.get("decisions", {}).get("comparisons", []):
		if group.get("goal", "") != agent.current_goal.get_id():
			continue
		for candidate: Dictionary in group.get("candidates", []):
			if candidate.get("reason", "") != "selected":
				continue
			var ids: Array[String] = []
			ids.assign(candidate.get("actions", []))
			return ids == full_ids or ids == remaining_ids
	return false


static func describe(agent: GoapAgent, report: Dictionary) -> String:
	if not matches_current_plan(agent, report):
		return "Waiting for a comparison of this plan."
	var decisions: Dictionary = report.decisions
	var group: Dictionary = {}
	for entry: Dictionary in decisions.get("comparisons", []):
		if entry.get("goal", "") == agent.current_goal.get_id():
			group = entry
			break
	var action_names := {}
	for action in agent.actions:
		action_names[action.get_id()] = String(action.name)
	var selected: Dictionary = {}
	var alternatives: Array[Dictionary] = []
	var invalid_count := 0
	for candidate: Dictionary in group.get("candidates", []):
		match String(candidate.get("reason", "")):
			"selected": selected = candidate
			"invalid": invalid_count += 1
			_: alternatives.append(candidate)
	alternatives.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("cost", INF)) < float(b.get("cost", INF))
	)
	var lines := PackedStringArray()
	lines.append("SELECTED ROUTE")
	lines.append(_route(selected, action_names))
	_append_route_steps(lines, selected, action_names, agent, "  ")
	lines.append("Cost %.2f · lowest evaluated valid cost for this goal" % float(selected.get("cost", agent.current_plan.cost)))
	lines.append("Step estimates use the current snapshot; planner costs above and below use the planning snapshot.")
	lines.append("")
	lines.append("OTHER ROUTES · SAME GOAL")
	if alternatives.is_empty():
		lines.append("No other complete route was evaluated.")
	for index in mini(alternatives.size(), 5):
		var item: Dictionary = alternatives[index]
		var reason := String(item.get("reason", ""))
		var amount: float = float(item.get("cost", 0.0))
		var detail := "Cost %.2f · higher cost" % amount
		if item.get("cost_is_lower_bound", false):
			detail = "Cost ≥ %.2f · stopped after this prefix exceeded the best" % amount
		elif reason == "tie_break":
			detail = "Cost %.2f · tied; step count or stable ID decided" % amount
		lines.append("%d. %s" % [index + 1, _route(item, action_names)])
		_append_route_steps(lines, item, action_names, agent, "   ")
		lines.append("   " + detail)
	if alternatives.size() > 5:
		lines.append("Showing 5 of %d recorded alternatives." % alternatives.size())
	if int(group.get("candidate_count", 0)) > group.get("candidates", []).size():
		lines.append("Planner searched %d candidates; %d have detailed records." % [
			int(group.candidate_count), group.candidates.size()
		])
	if invalid_count > 0:
		lines.append("%d incomplete or invalid route(s) omitted." % invalid_count)
	if not group.get("search_complete", true):
		lines.append("Search limit reached; a cheaper route may exist.")
	lines.append("")
	lines.append("OTHER GOALS")
	var other_goals := 0
	for entry: Dictionary in decisions.get("goals", []):
		if entry.get("id", "") == agent.current_goal.get_id():
			lines.append("%s · priority %s · selected before lower-priority goals" % [
				String(agent.current_goal.name), str(entry.get("priority", "?"))
			])
			continue
		if other_goals >= 4:
			continue
		lines.append("%s · priority %s · %s" % [
				String(entry.get("id", "")), str(entry.get("priority", "?")),
				_goal_reason(String(entry.get("reason", "")))
		])
		other_goals += 1
	return "\n".join(lines)


static func _route(candidate: Dictionary, names: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in candidate.get("actions", []).slice(0, 5):
		parts.append(names.get(id, str(id)))
	if int(candidate.get("steps", 0)) > 5:
		parts.append("…")
	return " → ".join(parts) if not parts.is_empty() else "(no actions)"


static func _append_route_steps(lines: PackedStringArray, candidate: Dictionary, names: Dictionary, agent: GoapAgent, indent: String) -> void:
	var ids: Array = candidate.get("actions", [])
	var estimates: Array[String] = []
	if agent.has_method("get_route_cost_labels"):
		estimates.assign(agent.call("get_route_cost_labels", ids))
	for index in ids.size():
		lines.append("%s%d. %s" % [indent, index + 1, names.get(ids[index], str(ids[index]))])
		if index < estimates.size() and not estimates[index].is_empty():
			lines.append("%s   %s" % [indent, estimates[index]])


static func _goal_reason(reason: String) -> String:
	match reason:
		"not_searched_higher_ranked_goal_succeeded": return "not searched after a higher-priority goal succeeded"
		"already_satisfied": return "already satisfied"
		"priority_disabled": return "priority disabled"
		"invalid": return "unavailable"
		"unreachable": return "no valid route"
		_: return reason.replace("_", " ")
