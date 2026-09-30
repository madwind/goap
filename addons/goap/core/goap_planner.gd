class_name GoapPlanner
extends RefCounted

## Backward dependency search, followed by forward dynamic-cost evaluation.
## Runtime workers run search and static cost models on isolated snapshots.
var actions: Array[GoapAction] = []
var max_nodes := 10000
var debug := false
var statistics: Dictionary = {}
var search_tree: Array = []
var snapshot_cache := GoapPlanningSnapshot.new()


static func is_pure_data(value: Variant) -> bool:
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_ARRAY:
			for item: Variant in value:
				if not is_pure_data(item):
					return false
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not is_pure_data(key) or not is_pure_data(value[key]):
					return false
	return true


static func search_snapshot(
	world_data: Dictionary[StringName, bool],
	goal_state_data: Dictionary[StringName, bool],
	records: Array,
	node_limit: int = 10000,
	record_trace: bool = false
) -> Dictionary:
	var started := Time.get_ticks_usec()
	var prepared := prepare_snapshot(records)
	var preparation_ms := (Time.get_ticks_usec() - started) / 1000.0
	var result := search_prepared(world_data, goal_state_data, prepared, node_limit, record_trace)
	result.statistics.preparation_time_ms = preparation_ms
	result.statistics.planning_time_ms += preparation_ms
	return result


## Reuse within one planning request. Records are already copied action snapshots;
## callers must treat both the records and this prepared data as immutable.
static func prepare_snapshot(records: Array) -> Dictionary:
	return GoapPlanningSnapshot.prepare(records)


static func search_prepared(
	world_data: Dictionary[StringName, bool],
	goal_state_data: Dictionary[StringName, bool],
	prepared: Dictionary,
	node_limit: int = 10000,
	record_trace: bool = false
) -> Dictionary:
	var search := GoapSearch.begin(world_data, goal_state_data, prepared, node_limit, record_trace)
	GoapSearch.advance(search)
	return GoapSearch.result(search)


func _init(available_actions: Array[GoapAction] = []) -> void:
	actions = available_actions.duplicate()
	actions.sort_custom(func(a: GoapAction, b: GoapAction) -> bool: return a.get_id() < b.get_id())


func create_action_snapshot() -> Array:
	var records: Array = []
	var ids: Dictionary = {}
	for action in actions:
		var record := GoapPlanningSnapshot.capture_action(action, ids)
		if record.is_empty():
			return []
		records.append(record)
	return records


## Optional loading-time warmup. Runtime availability and costs are still live.
func prewarm() -> bool:
	var records := create_action_snapshot()
	if records.size() != actions.size():
		return false
	snapshot_cache.get_or_prepare(records)
	return true


func find_plan(
	world: GoapWorldState,
	goal_state: GoapWorldState,
	cost_state: Dictionary = {},
	cost_contexts: Dictionary = {}
) -> GoapPlan:
	var started := Time.get_ticks_usec()
	var records := create_action_snapshot()
	if records.size() != actions.size() or not is_pure_data(cost_state):
		statistics = { "reason": "invalid_input", "search_complete": false }
		search_tree = []
		return null
	var models := capture_cost_models(null, cost_contexts)
	if models.size() != actions.size():
		return null
	var prepared := snapshot_cache.get_or_prepare(records)
	var world_data := world.to_dictionary()
	var goal_state_data := goal_state.to_dictionary()
	var preparation_ms := (Time.get_ticks_usec() - started) / 1000.0
	var work := GoapPlanningWork.begin(
		world_data,
		goal_state_data,
		prepared,
		models,
		cost_state.duplicate(true),
		max_nodes,
		debug
	)
	GoapPlanningWork.advance(work)
	var result: Dictionary = work.result
	result.statistics.preparation_time_ms = preparation_ms
	result.statistics.planning_time_ms += preparation_ms
	return GoapPlanningWork.materialize(result, self)


func capture_cost_models(agent: GoapAgent = null, contexts: Dictionary = {}) -> Array:
	var models: Array = []
	for action in actions:
		var entry := GoapPlanningSafety.capture(action, agent, contexts.get(action.get_id()))
		if entry.has("error"):
			statistics = {
				"reason": "unsafe_cost_model",
				"search_complete": false,
				"warning": entry.error
			}
			search_tree = []
			return []
		models.append(entry)
	return models
