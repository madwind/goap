class_name GoapSearch
extends RefCounted
## Resumable backward DFS. The entire continuation is pure data, owned by
## either the main thread or one worker at a time, never accessed concurrently.


static func begin(
	world: Dictionary[StringName, bool],
	goal_state: Dictionary[StringName, bool],
	prepared: Dictionary,
	node_limit: int,
	record_trace: bool
) -> Dictionary:
	return {
		"world": world,
		"prepared": prepared,
		"limit": maxi(0, node_limit),
		"debug": record_trace,
		"frontier": [
			{ "required": goal_state, "sequence": [], "ancestors": {}, "parent": -1, "action": "" }
		],
		"node": {},
		"ordered": [],
		"cursor": 0,
		"trace_id": -1,
		"done": false,
		"candidates": [],
		"candidate_trace_ids": [],
		"trace": [],
		"statistics": GoapPlanningData.search_statistics()
	}


static func advance(search: Dictionary, deadline_usec: int = 0) -> bool:
	var started := Time.get_ticks_usec()
	while not search.done and (deadline_usec == 0 or Time.get_ticks_usec() < deadline_usec):
		if search.node.is_empty():
			_expand(search)
		else:
			_regress(search)
	var stats: Dictionary = search.statistics
	stats.search_time_ms += (Time.get_ticks_usec() - started) / 1000.0
	stats.planning_time_ms = stats.search_time_ms
	stats.candidate_count = search.candidates.size()
	return search.done


static func result(search: Dictionary) -> Dictionary:
	return {
		"candidates": search.candidates,
		"candidate_trace_ids": search.candidate_trace_ids,
		"statistics": search.statistics,
		"trace": search.trace
	}


static func _expand(search: Dictionary) -> void:
	var stats: Dictionary = search.statistics
	if search.frontier.is_empty():
		stats.search_complete = true
		search.done = true
		return
	if stats.expanded_nodes >= search.limit:
		stats.search_complete = false
		search.done = true
		return
	var node: Dictionary = search.frontier.pop_back()
	var required: Dictionary[StringName, bool] = node.required
	var trace_id := -1
	if search.debug:
		trace_id = search.trace.size()
		search.trace.append(
			{
				"parent": node.parent,
				"action": node.action,
				"state": required.duplicate(),
				"reason": "expanded"
			}
		)
	stats.expanded_nodes += 1
	if _satisfies(search.world, required):
		search.candidates.append(node.sequence)
		if search.debug:
			search.candidate_trace_ids.append(trace_id)
			search.trace[trace_id].reason = "already satisfied"
		return
	var ancestors: Dictionary = node.ancestors.duplicate()
	ancestors[GoapWorldState.key_for(required)] = true
	node.ancestors = ancestors
	var relevant: Dictionary = {}
	var unmet_effects: Dictionary = {}
	var unmet_preconditions: Dictionary = {}
	var index: Dictionary = search.prepared.effect_index
	for name: StringName in required:
		var producers: Array = index.get(GoapPlanningSnapshot.fact_key(name, required[name]), [])
		if search.world.get(name, false) != required[name] and producers.is_empty():
			# No sequence can establish this unmet fact. Stop before expanding
			# unrelated inventory transitions around an impossible requirement.
			stats.pruned_nodes += 1
			stats.prune_reasons["unachievable"] = stats.prune_reasons.get("unachievable", 0) + 1
			if search.debug:
				search.trace[trace_id].reason = "unachievable"
			return
		for action_index: int in producers:
			relevant[action_index] = true
			if search.world.get(name, false) != required[name]:
				unmet_effects[action_index] = int(unmet_effects.get(action_index, 0)) + 1
	var ordered := relevant.keys()
	for action_index: int in ordered:
		var needed := 0
		for name: StringName in search.prepared.records[action_index].preconditions:
			if search.world.get(name, false) != search.prepared.records[action_index].preconditions[name]:
				needed += 1
		unmet_preconditions[action_index] = needed
	# DFS visits the last pushed branch first. Prefer actions establishing an
	# unmet requirement before permutations around already-satisfied facts.
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var a_needed := int(unmet_effects.get(a, 0))
		var b_needed := int(unmet_effects.get(b, 0))
		if a_needed != b_needed:
			return a_needed < b_needed
		var a_pre := int(unmet_preconditions[a])
		var b_pre := int(unmet_preconditions[b])
		return a_pre > b_pre if a_pre != b_pre else a > b
	)
	search.node = node
	search.ordered = ordered
	search.cursor = 0
	search.trace_id = trace_id


static func _regress(search: Dictionary) -> void:
	if search.cursor >= search.ordered.size():
		search.node = {}
		return
	var action_index: int = search.ordered[search.cursor]
	search.cursor += 1
	var node: Dictionary = search.node
	var record: Dictionary = search.prepared.records[action_index]
	var effects: Dictionary = record.effects
	var preconditions: Dictionary = record.preconditions
	var remaining: Dictionary[StringName, bool] = node.required.duplicate()
	var reason := ""
	for name: StringName in effects:
		if remaining.has(name):
			if remaining[name] != effects[name]:
				reason = "conflict"
			else:
				remaining.erase(name)
	for name: StringName in preconditions:
		if remaining.has(name) and remaining[name] != preconditions[name]:
			reason = "conflict"
		remaining[name] = preconditions[name]
	if reason.is_empty() and node.ancestors.has(GoapWorldState.key_for(remaining)):
		reason = "cycle / visited"
	if not reason.is_empty():
		var stats: Dictionary = search.statistics
		stats.pruned_nodes += 1
		stats.prune_reasons[reason] = stats.prune_reasons.get(reason, 0) + 1
		if search.debug:
			search.trace.append(
				{
					"parent": search.trace_id,
					"action": record.id,
					"state": remaining,
					"reason": reason
				}
			)
		return
	var sequence: Array = node.sequence.duplicate()
	sequence.push_front(action_index)
	search.frontier.append(
		{
			"required": remaining,
			"sequence": sequence,
			"ancestors": node.ancestors,
			"parent": search.trace_id,
			"action": record.id
		}
	)


static func _satisfies(world: Dictionary, required: Dictionary) -> bool:
	for name: StringName in required:
		if world.get(name, false) != required[name]:
			return false
	return true
