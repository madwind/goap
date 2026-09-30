class_name GoapPlanningRequest
extends RefCounted
## Main-thread request state. Worker data contains copied values and audited
## static cost-model scripts; runtime actions never cross the worker boundary.

enum Stage {
	SETUP,
	GOALS,
	COST_SNAPSHOT,
	ACTIONS,
	INDEX,
	BUILD_INDEX,
	START_GOAL,
	WORK,
}

var generation: int
var phase := GoapPlanningData.Phase.PREPARING
var finished := false
var cancelled := false
var no_goals := false
var planner := GoapPlanner.new()
var plan: GoapPlan
var goal: GoapGoal
var statistics: Dictionary = {}
var totals := {
	"searched_goals": 0,
	"expanded_nodes": 0,
	"pruned_nodes": 0,
	"candidate_count": 0,
	"preparation_time_ms": 0.0,
	"search_time_ms": 0.0,
	"evaluation_time_ms": 0.0,
	"max_main_step_ms": 0.0,
	"max_cost_callback_ms": 0.0
}
var task_id := -1
var worker_data: Dictionary = {}
var goal_index := 0
var _agent: WeakRef
var _started_usec: int
var _stage := Stage.SETUP
var _world: GoapWorldState
var _cost_state: Dictionary
var _source_goals: Array[GoapGoal] = []
var _source_actions: Array[GoapAction] = []
var _ranked: Array[Dictionary] = []
var _entries: Array[Dictionary] = []
var _goal_ids: Dictionary = {}
var _action_ids: Dictionary = {}
var _prepared := GoapPlanningSnapshot.empty_prepared()
var _cost_models: Array = []
var _records: Array = []
var _cursor := 0
var _asynchronous := true
var _capture_decisions := false
var _goal_decisions: Array[Dictionary] = []
var _action_decisions: Array[Dictionary] = []
var _cost_comparisons: Array[Dictionary] = []


static func planning_slice(data: Dictionary, budget_usec: int) -> void:
	GoapPlanningWork.advance(data, Time.get_ticks_usec() + budget_usec)


func _init(agent: GoapAgent) -> void:
	_agent = weakref(agent)
	generation = agent.planning_generation
	_started_usec = agent.planning_requested_usec if agent.planning_requested_usec > 0 else Time.get_ticks_usec()
	_asynchronous = agent.asynchronous_planning
	_capture_decisions = agent.diagnostics_enabled
	planner.max_nodes = agent.max_planning_nodes
	planner.debug = agent.debug
	planner.snapshot_cache = agent.planning_cache


func is_current() -> bool:
	var agent: GoapAgent = _agent.get_ref()
	return not cancelled and agent != null and agent.planning_generation == generation


## A false return means the request is waiting for a worker/worker slot.
func advance(deadline_usec: int, scheduler: GoapPlanningScheduler) -> bool:
	var progressed := false
	while not finished and Time.get_ticks_usec() < deadline_usec:
		if not is_current():
			cancelled = true
			finished = true
			return true
		if task_id != -1:
			return progressed
		var started := Time.get_ticks_usec()
		var preparing := phase == GoapPlanningData.Phase.PREPARING
		if not _step(deadline_usec, scheduler):
			return progressed
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		totals.max_main_step_ms = maxf(totals.max_main_step_ms, elapsed)
		if preparing:
			totals.preparation_time_ms += elapsed
		progressed = true
	return progressed


func report() -> Dictionary:
	var report := statistics.duplicate()
	report.generation = generation
	if not finished:
		report.reason = "pending"
		report.search_complete = null
	report.request_finished = finished
	report.phase = GoapPlanningData.phase_name(phase)
	var aggregate := totals.duplicate()
	aggregate.planning_time_ms = aggregate.preparation_time_ms + aggregate.search_time_ms + aggregate.evaluation_time_ms
	aggregate.latency_ms = (Time.get_ticks_usec() - _started_usec) / 1000.0
	report.request = aggregate
	if finished and _capture_decisions:
		report.decisions = { "goals": _goal_decisions.duplicate(true), "actions": _action_decisions.duplicate(true), "comparisons": _cost_comparisons.duplicate(true), "bounded": true, "limits": { "goals": 128, "actions": 128 } }
	return report


func _step(deadline_usec: int, scheduler: GoapPlanningScheduler) -> bool:
	var agent: GoapAgent = _agent.get_ref()
	match _stage:
		Stage.SETUP:
			agent.discard_invalid_plan()
			_world = agent.world_state.duplicate()
			_source_goals = agent.goals.duplicate()
			_source_actions = agent.actions.duplicate()
			_stage = Stage.GOALS
		Stage.GOALS:
			if _cursor < _source_goals.size():
				var item := _source_goals[_cursor]
				_cursor += 1
				var id := item.get_id()
				if id.is_empty() or _goal_ids.has(id):
					_fail("duplicate_goal_id")
					return true
				_goal_ids[id] = true
				var priority := agent.goal_priority(item, _world)
				var valid := item.is_valid(_world)
				var satisfied := valid and _world.satisfies(item.goal_state)
				var reason := "candidate"
				if not valid or satisfied or not is_finite(priority) or priority <= 0:
					reason = "invalid" if not valid else ("already_satisfied" if satisfied else "priority_disabled")
				else:
					_ranked.append(
						{
							"goal": item,
							"id": id,
							"priority": priority,
							"goal_state": item.goal_state.to_dictionary()
						}
					)
				if _capture_decisions and _goal_decisions.size() < 128:
					_goal_decisions.append({ "id": id, "priority": priority if is_finite(priority) else null, "reason": reason })
			else:
				_ranked.sort_custom(
					func(a: Dictionary, b: Dictionary) -> bool:
						return a.priority > b.priority if a.priority != b.priority else a.id < b.id
				)
				if _ranked.is_empty():
					no_goals = true
					finished = true
					phase = GoapPlanningData.Phase.COMPLETED
					statistics = { "reason": "no_goal", "search_complete": true }
					return true
				_stage = Stage.COST_SNAPSHOT
				_cursor = 0
		Stage.COST_SNAPSHOT:
			var state := agent.capture_cost_state()
			if not GoapPlanner.is_pure_data(state):
				GoapPlanningSafety.warn(
					GoapPlanningSafety.impure_path(state, "Agent._capture_cost_state")
				)
				_fail("invalid_input")
				return true
			_cost_state = state.duplicate(true)
			_stage = Stage.ACTIONS
		Stage.ACTIONS:
			if _cursor < _source_actions.size():
				var action := _source_actions[_cursor]
				_cursor += 1
				if not action.is_valid(agent):
					_record_action_decision(action, "unavailable")
					return true
				var record := GoapPlanningSnapshot.capture_action(action, _action_ids)
				if record.is_empty():
					_fail("invalid_input")
					return true
				var cost_model := GoapPlanningSafety.capture(action, agent)
				if cost_model.has("error"):
					_record_action_decision(action, "unsafe_cost_model")
					_fail("unsafe_cost_model")
					statistics.warning = cost_model.error
					return true
				_entries.append(
					{
						"action": action,
						"id": record.id,
						"record": record,
						"cost_model": cost_model
					}
				)
				_record_action_decision(action, "available")
			else:
				_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
				_cursor = 0
				_stage = Stage.INDEX
		Stage.INDEX:
			if _cursor < _entries.size():
				var entry: Dictionary = _entries[_cursor]
				planner.actions.append(entry.action)
				_cost_models.append(entry.cost_model)
				_records.append(entry.record)
				_cursor += 1
			else:
				var cached := planner.snapshot_cache.reuse(_records)
				if not cached.is_empty():
					_prepared = cached
					_stage = Stage.START_GOAL
				else:
					_cursor = 0
					_stage = Stage.BUILD_INDEX
		Stage.BUILD_INDEX:
			if _cursor < _records.size():
				GoapPlanningSnapshot.append_record(_prepared, _records[_cursor])
				_cursor += 1
			else:
				planner.snapshot_cache.remember(_prepared)
				_stage = Stage.START_GOAL
		Stage.START_GOAL:
			phase = GoapPlanningData.Phase.SEARCHING
			goal = _ranked[goal_index].goal
			worker_data = GoapPlanningWork.begin(
				_world.to_dictionary(),
				_ranked[goal_index].goal_state,
				_prepared,
				_cost_models,
				_cost_state,
				planner.max_nodes,
				planner.debug,
				_capture_decisions
			)
			_stage = Stage.WORK
		Stage.WORK:
			phase = worker_data.phase
			if phase == GoapPlanningData.Phase.COMPLETED:
				plan = GoapPlanningWork.materialize(worker_data.result, planner)
				statistics = planner.statistics.duplicate(true)
				if _capture_decisions:
					var recorded_goal := false
					for entry in _goal_decisions:
						if entry.id == goal.get_id():
							entry.reason = "selected" if plan != null else statistics.get("reason", "unreachable")
							recorded_goal = true
					if plan != null and not recorded_goal:
						if _goal_decisions.size() >= 128:
							_goal_decisions.pop_back()
						_goal_decisions.append({ "id": goal.get_id(), "priority": _ranked[goal_index].priority, "reason": "selected" })
					var comparison := { "goal": goal.get_id(), "search_complete": statistics.get("search_complete", false), "selected_cost": statistics.get("cost"), "candidates": statistics.get("candidate_comparisons", []), "candidate_count": statistics.get("candidate_count", 0) }
					_cost_comparisons.append(comparison)
					statistics.erase("candidate_comparisons")
				totals.searched_goals += 1
				totals.evaluated_actions = totals.get("evaluated_actions", 0) + statistics.get(
					"evaluated_actions",
					0
				)
				for key in [
					"expanded_nodes",
					"pruned_nodes",
					"candidate_count",
					"search_time_ms",
					"evaluation_time_ms"
				]:
					totals[key] += statistics[key]
				totals.max_cost_callback_ms = maxf(
					totals.max_cost_callback_ms,
					statistics.max_cost_callback_ms
				)
				worker_data = {}
				if plan != null or goal_index + 1 == _ranked.size():
					if plan != null and _capture_decisions:
						for entry in _goal_decisions:
							if entry.reason == "candidate":
								entry.reason = "not_searched_higher_ranked_goal_succeeded"
					finished = true
					phase = GoapPlanningData.Phase.COMPLETED
				else:
					goal_index += 1
					phase = GoapPlanningData.Phase.SEARCHING
					_stage = Stage.START_GOAL
			elif _asynchronous:
				return scheduler.dispatch(self)
			else:
				GoapPlanningWork.advance(worker_data, deadline_usec)
	return true


func _fail(reason: String) -> void:
	statistics = { "reason": reason, "search_complete": false }
	finished = true
	phase = GoapPlanningData.Phase.COMPLETED


func _record_action_decision(action: GoapAction, reason: String) -> void:
	if _capture_decisions and _action_decisions.size() < 128:
		_action_decisions.append({ "id": action.get_id(), "reason": reason })
