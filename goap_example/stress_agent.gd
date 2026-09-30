extends GoapAgent
## A finite benchmark round: search every generated goal independently, without
## executing actions or allowing survival observations to replace the requests.

var goal_count := 2
var steps_per_goal := 5
var alternatives_per_step := 3
var completed_goals := 0
var _benchmark_goals: Array[GoapGoal] = []
var _last_report: Dictionary = {}
var _progress: Dictionary = {}


static func candidates_per_goal(steps: int, alternatives: int) -> int:
	var count := 1
	for step in steps:
		count *= alternatives
	return count


func _enter_tree() -> void:
	for goal_index in goal_count:
		for step in steps_per_goal:
			for alternative in alternatives_per_step:
				var action := GoapAction.new()
				action.name = "G%d_S%02d_A%d" % [goal_index + 1, step + 1, alternative + 1]
				if step > 0:
					action.preconditions.set_state(_fact(goal_index, step - 1), true)
				action.effects.set_state(_fact(goal_index, step), true)
				actions.append(action)
		var goal := GoapGoal.new()
		goal.name = "Stress goal %d" % (goal_index + 1)
		goal.goal_state.set_state(_fact(goal_index, steps_per_goal - 1), true)
		_benchmark_goals.append(goal)
	goals.assign([_benchmark_goals[0]])
	super._enter_tree()


func _physics_process(_delta: float) -> void:
	if is_planning():
		GoapPlanningScheduler.for_tree(get_tree()).enqueue(self)


func advance_planning(deadline_usec: int, scheduler: GoapPlanningScheduler) -> bool:
	# Read only after the scheduler joined the worker; UI reads the copied snapshot.
	if _budget_request != null and _budget_request.is_current() and _budget_request.task_id == -1:
		var work := _budget_request.worker_data
		if not work.is_empty():
			var measured: Dictionary = work.search.statistics
			_progress = {
				"candidates": int(measured.get("candidate_count", 0)),
				"expanded": int(measured.get("expanded_nodes", 0)),
				"phase": GoapPlanningData.phase_name(work.phase)
			}
	var progressed := super.advance_planning(deadline_usec, scheduler)
	if not planning_statistics.get("request_finished", false) or planning_statistics.get(
		"reason"
	) == "pending" or is_same(_last_report, planning_statistics):
		return progressed
	_last_report = planning_statistics
	_progress.clear()
	completed_goals += 1
	if completed_goals < goal_count:
		_discard_plan()
		goals.assign([_benchmark_goals[completed_goals]])
		request_replan()
	return progressed


func restart_round() -> void:
	_discard_plan()
	_progress.clear()
	completed_goals = 0
	goals.assign([_benchmark_goals[0]])
	request_replan()


func live_progress() -> Dictionary:
	if not is_planning():
		return {}
	var snapshot := _progress.duplicate()
	snapshot.age_ms = (Time.get_ticks_usec() - _requested_usec) / 1000.0
	return snapshot


func _fact(goal_index: int, step: int) -> StringName:
	return StringName("goal_%d_step_%d" % [goal_index, step])
