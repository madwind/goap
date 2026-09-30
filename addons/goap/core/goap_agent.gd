class_name GoapAgent
extends Node

signal plan_updated
## Emitted once after a completed request has been applied (including no-goal/failure).
signal planning_measured(report: Dictionary)

@export_dir var goap_script_folder: String
@export var fact_key_script: Script
@export var asynchronous_planning := true
@export var max_planning_nodes := 10000
@export var debug := false

var goals: Array[GoapGoal] = []
var actions: Array[GoapAction] = []
var world_state: GoapWorldState
var current_action: GoapAction
var current_goal: GoapGoal
var _planner: GoapPlanner
var _current_plan: GoapPlan
var current_plan: GoapPlan:
	get:
		return _current_plan
var planning_trace: Array:
	get:
		return _planner.search_tree if _planner != null else []
var planning_generation: int:
	get:
		return _generation
var planning_requested_usec: int:
	get:
		return _requested_usec
var is_suspended: bool:
	get:
		return _suspended
var _suspended := false
var _initial_observation_pending := true
var planning_statistics: Dictionary = {}
var diagnostics_enabled := false
var diagnostic_dropped := 0
var _diagnostic_sequence := 0
var _diagnostic_events: Array[Dictionary] = []
var _diagnostic_world: Dictionary = {}
var planning_cache := GoapPlanningSnapshot.new()
## Game-owned parent; planning does not require a 2D/3D character base class.
var actor: Node:
	get:
		return get_parent()

var _generation := 0
var _plan_revision := 0
var _planning_requested := false
var _requested_usec := 0
var _budget_request: GoapPlanningRequest
var _scheduler: GoapPlanningScheduler
var _observation_before: Dictionary[StringName, bool] = {}
var _publishing_observation := false


static func _script_paths(folder: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for file in ResourceLoader.list_directory(folder):
		if file.ends_with(".gd"):
			paths.append(folder.path_join(file))
	paths.sort()
	return paths


func _enter_tree() -> void:
	init_goap()


func _ready() -> void:
	request_replan("initial")


func _physics_process(delta: float) -> void:
	if _suspended:
		return
	if _initial_observation_pending:
		_initial_observation_pending = false
		refresh_world_state()
	_process_goap(delta)
	# Consume ability completion before publishing consumed resources/ingredients.
	if not _suspended:
		refresh_world_state()


func _process_goap(delta: float) -> void:
	if current_goal != null and (
		not current_goal.is_valid(world_state)
		or world_state.satisfies(current_goal.goal_state)
		or goal_priority(current_goal, world_state) <= 0
	):
		# Keep a usable action running while its replacement is being planned.
		if not is_planning():
			request_replan("goal_changed")
	if (_planning_requested or _budget_request != null) and is_inside_tree():
		if not is_instance_valid(_scheduler):
			_scheduler = GoapPlanningScheduler.for_tree(get_tree())
		_scheduler.enqueue(self)
	_follow_plan(delta)


func init_goap(script_folder := goap_script_folder) -> void:
	if world_state == null:
		world_state = GoapWorldState.new()
	if not world_state.state_changed.is_connected(_on_world_state_changed):
		world_state.state_changed.connect(_on_world_state_changed)
	if not script_folder.is_empty():
		load_goap_actions(script_folder)
		load_goap_goals(script_folder)
	_planner = GoapPlanner.new(actions)
	_planner.snapshot_cache = planning_cache


## Call after loading/configuring actions, e.g. during a loading screen.
## Normal requests also populate the cache lazily within the shared budget.
func prewarm_planning() -> bool:
	var planner := GoapPlanner.new(actions)
	planner.snapshot_cache = planning_cache
	return planner.prewarm()


func advance_planning(deadline_usec: int, scheduler: GoapPlanningScheduler) -> bool:
	if _suspended:
		return false
	if _budget_request != null and not _budget_request.is_current():
		_budget_request.cancelled = true
		_budget_request = null
	if _budget_request == null:
		if not _planning_requested:
			return false
		_planning_requested = false
		_budget_request = GoapPlanningRequest.new(self)
	var request := _budget_request
	var progressed := request.advance(deadline_usec, scheduler)
	if not request.is_current():
		request.cancelled = true
		_budget_request = null
		return true
	if progressed:
		planning_statistics = request.report()
	if not request.finished:
		return progressed
	if diagnostics_enabled:
		record_diagnostic("planning_completed", {
			"reason": planning_statistics.get("reason", ""),
			"goal": request.goal.get_id() if request.goal != null else "",
			"report": planning_statistics.duplicate(true),
		})
	var completed_report := planning_statistics
	_budget_request = null
	if request.no_goals:
		_discard_obsolete_plan()
		planning_measured.emit(completed_report)
		return true
	_planner = request.planner
	if request.plan != null:
		if not _same_remaining_plan(request.goal, request.plan):
			_discard_plan()
			# Stop/signal callbacks may synchronously invalidate this result.
			if request.is_current():
				current_goal = request.goal
				_current_plan = request.plan
				plan_updated.emit()
	else:
		_discard_obsolete_plan()
		plan_updated.emit()
	planning_measured.emit(completed_report)
	return true


func _same_remaining_plan(goal: GoapGoal, candidate: GoapPlan) -> bool:
	# A fresh search with the same route must not restart a running action.
	if _current_plan == null or current_goal != goal:
		return false
	var remaining := _current_plan.actions.size() - _current_plan.step
	if remaining != candidate.actions.size():
		return false
	for index in remaining:
		if _current_plan.actions[_current_plan.step + index] != candidate.actions[index]:
			return false
	return true


func request_replan(reason := "requested") -> void:
	if _suspended:
		return
	_generation += 1
	_planning_requested = true
	_requested_usec = Time.get_ticks_usec()
	if diagnostics_enabled:
		record_diagnostic("replan_requested", { "reason": reason })


func is_planning() -> bool:
	return _planning_requested or _budget_request != null


## Cancel pending computation. The current plan remains active.
func cancel_planning() -> void:
	if diagnostics_enabled and is_planning():
		record_diagnostic("planning_cancelled", { "reason": "cancel_planning" })
	_generation += 1
	_planning_requested = false
	if _budget_request != null:
		_budget_request.cancelled = true
		_budget_request = null
	if is_instance_valid(_scheduler):
		_scheduler.remove(self)


## Stop execution and ignore replanning until resume().
func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	if diagnostics_enabled:
		record_diagnostic("suspended", {})
	cancel_planning()
	_discard_plan()


func resume() -> void:
	if not _suspended:
		return
	_suspended = false
	request_replan("resumed")


func capture_cost_state() -> Dictionary:
	return _capture_cost_state()


## Scheduler registration lets cancellation remove even an unstarted request.
func attach_planning_scheduler(scheduler: GoapPlanningScheduler) -> void:
	_scheduler = scheduler


func discard_invalid_plan() -> void:
	if _current_plan != null and (
		not _current_plan.is_valid_from(world_state)
	):
		if diagnostics_enabled:
			record_diagnostic("plan_invalidated", { "reason": "remaining_conditions_invalid" })
		_discard_plan()


func _discard_obsolete_plan() -> void:
	if _current_plan != null and current_goal != null and (
		not current_goal.is_valid(world_state)
		or world_state.satisfies(current_goal.goal_state)
		or goal_priority(current_goal, world_state) <= 0
	):
		_discard_plan()


func goal_priority(goal: GoapGoal, state: GoapWorldState) -> float:
	if goal == null:
		return 0.0
	return goal.get_priority(state)


func load_goap_actions(script_folder: String) -> void:
	actions.clear()
	for script_path in _script_paths(script_folder.path_join("actions")):
		var action: Variant = load(script_path).new()
		if action is GoapAction:
			actions.append(action)


func load_goap_goals(script_folder: String) -> void:
	goals.clear()
	for script_path in _script_paths(script_folder.path_join("goals")):
		var goal: Variant = load(script_path).new()
		if goal is GoapGoal:
			goals.append(goal)


## Override to supply the agent's complete current knowledge, including its own
## state. Discover providers using your sensors, scene traversal or spatial index,
## then combine their observations with GoapWorldStateProvider.collect().
## null retains manually managed facts; an empty state clears all observations.
## This hook is never called by detached editor previews or planning workers.
func _observe_world_state() -> GoapWorldState:
	return null


## Called after execution each physics tick; may also be called by game events.
func refresh_world_state() -> void:
	if world_state == null:
		return
	var observed := _observe_world_state()
	if observed != null:
		_observation_before = world_state.snapshot()
		_publishing_observation = true
		world_state.replace(observed)
		_publishing_observation = false
		_observation_before = {}


## Games may keep a valid running plan when an observation adds an irrelevant fact.
## Direct state writes and action effects still request replanning normally.
func _should_replan_after_observation(_before: Dictionary[StringName, bool], _after: GoapWorldState) -> bool:
	return true


## Optional readable name for generated state keys. Keys remain the planning identity.
func get_world_state_label(key: StringName) -> String:
	return String(key)


## Optional provenance for generated facts. Each entry has a label and resource
## path, plus an optional method name for script navigation in the editor.
func get_world_state_sources(_key: StringName) -> Array[Dictionary]:
	return []


## Override to capture positions, risk, resources, etc. on the main thread.
func _capture_cost_state() -> Dictionary:
	return {}


func _follow_plan(delta: float) -> void:
	if _current_plan == null:
		return
	var plan := _current_plan
	var status := plan.execute(self, delta)
	# Runtime callbacks may synchronously preempt this agent.
	if _current_plan != plan:
		return
	if status == GoapAction.Status.FAILURE:
		if not _discard_plan():
			return
		request_replan("action_failed")
	elif status == GoapAction.Status.SUCCESS:
		_complete_or_discard()


func _complete_or_discard() -> void:
	var completed := current_goal != null and world_state.satisfies(current_goal.goal_state)
	if not _discard_plan():
		return
	request_replan("goal_completed" if completed else "goal_invalidated")


func _discard_plan() -> bool:
	_plan_revision += 1
	var revision := _plan_revision
	var old := _current_plan
	_current_plan = null
	current_goal = null
	if old != null:
		old.stop(self)
	plan_updated.emit()
	return revision == _plan_revision


func _on_world_state_changed() -> void:
	if diagnostics_enabled:
		var current := world_state.to_dictionary()
		var changes: Array[Dictionary] = []
		var keys := _diagnostic_world.keys()
		for key in current:
			if not keys.has(key):
				keys.append(key)
		for key in keys:
			if _diagnostic_world.get(key, false) != current.get(key, false):
				changes.append({ "fact": String(key), "before": _diagnostic_world.get(key, false), "after": current.get(key, false) })
		_diagnostic_world = current
		record_diagnostic("facts_changed", { "changes": changes })
	if not _publishing_observation or _should_replan_after_observation(_observation_before, world_state):
		request_replan("world_state_changed")


func begin_diagnostics() -> void:
	diagnostics_enabled = true
	planning_statistics.erase("decisions")
	_diagnostic_events.clear()
	diagnostic_dropped = 0
	_diagnostic_world = world_state.to_dictionary() if world_state != null else {}
	record_diagnostic("observation_started", {})


func end_diagnostics() -> void:
	diagnostics_enabled = false
	planning_statistics.erase("decisions")
	_diagnostic_events.clear()
	_diagnostic_world.clear()


## Buffer data, never invoke observer callbacks inside action lifecycle code.
func record_diagnostic(type: String, data: Dictionary) -> void:
	if not diagnostics_enabled:
		return
	_diagnostic_sequence += 1
	_diagnostic_events.append({
		"sequence": _diagnostic_sequence, "time_usec": Time.get_ticks_usec(),
		"generation": _generation, "type": type, "data": data,
	})
	if _diagnostic_events.size() > 128:
		_diagnostic_events.pop_front()
		diagnostic_dropped += 1


func take_diagnostic_events() -> Array[Dictionary]:
	var events := _diagnostic_events
	_diagnostic_events = []
	return events


func _exit_tree() -> void:
	var was_suspended := _suspended
	suspend()
	_suspended = was_suspended
