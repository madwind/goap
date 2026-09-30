class_name GoapEvaluation
extends RefCounted
## Thread-owned evaluation of snapshot records.

var search_result: Dictionary
var records: Array
var world: Dictionary
var goal_state: Dictionary
var initial_cost_state: Dictionary
var statistics: Dictionary
var best_action_indices: Array = []
var best_cost := INF
var found := false
var finished := false
var candidate_index := 0
var action_index := 0
var max_callback_usec := 0
var cost_models: Array
var warnings: Array[String] = []
var _best_trace := -1
var _active := false
var _cost := 0.0
var _facts: Dictionary
var _cost_state: Dictionary
var _elapsed_usec := 0
var _capture_comparisons := false
var _comparisons: Array[Dictionary] = []
var _best_candidate_index := -1
var _comparisons_finalized := false


func _init(
	initial_search_result: Dictionary,
	action_records: Array,
	initial: Dictionary,
	goal_state: Dictionary,
	cost_state: Dictionary,
	models: Array,
	capture_comparisons: bool = false
) -> void:
	search_result = initial_search_result
	records = action_records
	world = initial
	self.goal_state = goal_state
	initial_cost_state = cost_state
	cost_models = models
	_capture_comparisons = capture_comparisons
	statistics = search_result.statistics.duplicate()


func advance(deadline_usec: int = 0) -> bool:
	var started := Time.get_ticks_usec()
	while not finished and (deadline_usec == 0 or Time.get_ticks_usec() < deadline_usec):
		_step()
	_elapsed_usec += Time.get_ticks_usec() - started
	statistics.evaluation_time_ms = _elapsed_usec / 1000.0
	statistics.max_cost_callback_ms = max_callback_usec / 1000.0
	if finished:
		statistics.planning_time_ms = search_result.statistics.planning_time_ms + statistics.evaluation_time_ms
		statistics.cost = best_cost if found else null
		statistics.reason = "found" if found else "unreachable"
		if not statistics.search_complete:
			statistics.reason = "node_limit"
		if _capture_comparisons and not _comparisons_finalized:
			_comparisons_finalized = true
			var best_ids: Array[String] = []
			for index in best_action_indices:
				best_ids.append(records[index].id)
			var winner_recorded := false
			for comparison in _comparisons:
				if comparison.reason == "valid_candidate":
					if comparison.index == _best_candidate_index:
						comparison.reason = "selected"
						winner_recorded = true
					else:
						comparison.reason = "higher_cost" if comparison.cost > best_cost else "tie_break"
			if found and not winner_recorded:
				_comparisons.append({ "actions": best_ids, "steps": best_action_indices.size(), "cost": best_cost, "cost_is_lower_bound": false, "reason": "selected" })
			statistics.candidate_comparisons = _comparisons
	return finished


func _step() -> void:
	if candidate_index >= search_result.candidates.size():
		finished = true
		return
	var sequence: Array = search_result.candidates[candidate_index]
	if not _active:
		_active = true
		_cost = 0.0
		_facts = world.duplicate()
		_cost_state = initial_cost_state.duplicate(true)
		action_index = 0
		return
	if action_index >= sequence.size():
		_complete_candidate("" if GoapSearch._satisfies(_facts, goal_state) else "invalid")
		return
	var record: Dictionary = records[sequence[action_index]]
	var entry: Dictionary = cost_models[sequence[action_index]]
	if not GoapSearch._satisfies(_facts, record.preconditions):
		_complete_candidate("invalid")
		return
	var model: GDScript = entry.model
	# The base model uses the action's captured fixed cost and has no simulated side effects.
	var default_model := model == GoapCostModel
	var started := Time.get_ticks_usec()
	var cost: float = float(entry.cost) if default_model else model.get_cost(_cost_state, entry.context)
	statistics.evaluated_actions = statistics.get("evaluated_actions", 0) + 1
	max_callback_usec = maxi(max_callback_usec, Time.get_ticks_usec() - started)
	if not default_model and not GoapPlanner.is_pure_data(_cost_state):
		warnings.append(
			"%s.get_cost inserted a live object/callable into simulation; use snapshot values only" % record.id
		)
		_complete_candidate("invalid")
		return
	if not is_finite(cost) or cost < 0.0:
		_complete_candidate("invalid")
		return
	_cost += cost
	if not is_finite(_cost):
		_complete_candidate("invalid")
		return
	if found and _cost > best_cost:
		_complete_candidate("higher cost")
		return
	if not default_model:
		started = Time.get_ticks_usec()
		model.apply_cost_effect(_cost_state, entry.context)
		max_callback_usec = maxi(max_callback_usec, Time.get_ticks_usec() - started)
		if not GoapPlanner.is_pure_data(_cost_state):
			warnings.append(
				"%s.apply_cost_effect inserted a live object/callable into simulation; use snapshot values only" % record.id
			)
			_complete_candidate("invalid")
			return
	_facts.merge(record.effects, true)
	action_index += 1


func _complete_candidate(rejection: String) -> void:
	var trace: Array = search_result.trace
	var trace_id: int = search_result.candidate_trace_ids[
		candidate_index
	] if not trace.is_empty() else -1
	var sequence: Array = search_result.candidates[candidate_index]
	if _capture_comparisons:
		var ids: Array[String] = []
		for index in sequence:
			ids.append(records[index].id)
		_comparisons.append({ "index": candidate_index, "actions": ids, "steps": sequence.size(), "cost": _cost if is_finite(_cost) and rejection != "invalid" else null, "cost_is_lower_bound": rejection == "higher cost", "reason": "valid_candidate" if rejection.is_empty() else rejection })
	if not rejection.is_empty():
		statistics.pruned_candidates = statistics.get("pruned_candidates", 0) + 1
		if rejection == "invalid":
			statistics.invalid_candidates = statistics.get("invalid_candidates", 0) + 1
		if trace_id != -1:
			trace[trace_id].reason = rejection
	elif not found or _is_better(sequence):
		if _best_trace != -1:
			trace[_best_trace].reason = "higher cost / tie break"
		best_action_indices = sequence
		_best_candidate_index = candidate_index
		best_cost = _cost
		found = true
		_best_trace = trace_id
		if trace_id != -1:
			trace[trace_id].reason = "selected"
	elif trace_id != -1:
		trace[trace_id].reason = "higher cost / tie break"
	candidate_index += 1
	_active = false
	_facts = {}
	_cost_state = {}


func _is_better(sequence: Array) -> bool:
	if _cost != best_cost:
		return _cost < best_cost
	if sequence.size() != best_action_indices.size():
		return sequence.size() < best_action_indices.size()
	return _ids_before(sequence, best_action_indices)


func _ids_before(sequence: Array, other: Array) -> bool:
	for index in mini(sequence.size(), other.size()):
		var left: String = records[sequence[index]].id
		var right: String = records[other[index]].id
		if left != right:
			return left < right
	return sequence.size() < other.size()
