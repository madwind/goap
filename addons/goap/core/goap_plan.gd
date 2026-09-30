class_name GoapPlan
extends RefCounted

signal action_succeeded(is_last_step: bool)

var actions: Array[GoapAction] = []
var cost := 0.0
var step := 0
var planning_time_ms := 0.0
var expanded_nodes := 0
var pruned_nodes := 0
var search_complete := true
var _started := false
var _revision := 0
var _executing := false


func execute(agent: GoapAgent, delta: float) -> GoapAction.Status:
	# Callbacks may stop this plan or recursively try to execute it.
	if _executing:
		return GoapAction.Status.RUNNING
	_executing = true
	var result := _execute(agent, delta)
	_executing = false
	return result


func stop(agent: GoapAgent) -> void:
	_revision += 1
	_stop_action(agent)


func is_valid_from(state: GoapWorldState) -> bool:
	var simulated := state.duplicate()
	for index in range(step, actions.size()):
		if not simulated.satisfies(actions[index].preconditions):
			return false
		simulated.merge(actions[index].effects, false)
	return true


func _execute(agent: GoapAgent, delta: float) -> GoapAction.Status:
	var revision := _revision
	var owner_plan := agent.current_plan
	if step >= actions.size():
		return GoapAction.Status.SUCCESS
	var action := actions[step]
	var conditions_met := agent.world_state.satisfies(action.preconditions)
	var valid := conditions_met and action.is_valid(agent)
	if _revision != revision or agent.current_plan != owner_plan:
		return GoapAction.Status.FAILURE
	if not valid:
		if agent.diagnostics_enabled:
			agent.record_diagnostic("action_failed", {
				"action": action.get_id(), "step": step, "plan_id": get_instance_id(),
				"reason": "unavailable" if conditions_met else "preconditions",
				"missing": action.preconditions.difference(agent.world_state).to_dictionary(),
			})
		stop(agent)
		return GoapAction.Status.FAILURE
	if not _started:
		_started = true
		agent.current_action = action
		if agent.diagnostics_enabled:
			agent.record_diagnostic("action_started", { "action": action.get_id(), "step": step, "plan_id": get_instance_id() })
		action.start(agent)
		if not _started or _revision != revision or agent.current_plan != owner_plan:
			return GoapAction.Status.FAILURE
	var status := action.perform(agent, delta)
	if not _started or _revision != revision or agent.current_plan != owner_plan:
		return GoapAction.Status.FAILURE
	if status != GoapAction.Status.RUNNING:
		# Normal cleanup does not invalidate this execution; a nested stop does.
		_stop_action(agent, "success" if status == GoapAction.Status.SUCCESS else "failure")
		if _revision != revision or agent.current_plan != owner_plan:
			return GoapAction.Status.FAILURE
	if status == GoapAction.Status.SUCCESS:
		agent.world_state.merge(action.effects)
		# State-change observers may preempt after the effects are committed.
		if _revision != revision or agent.current_plan != owner_plan:
			return GoapAction.Status.FAILURE
		if agent.diagnostics_enabled:
			agent.record_diagnostic("action_succeeded", { "action": action.get_id(), "step": step, "plan_id": get_instance_id() })
		action_succeeded.emit(step == actions.size() - 1)
		if _revision != revision or agent.current_plan != owner_plan:
			return GoapAction.Status.FAILURE
		step += 1
		return GoapAction.Status.SUCCESS if step == actions.size() else GoapAction.Status.RUNNING
	if status == GoapAction.Status.FAILURE and agent.diagnostics_enabled:
		agent.record_diagnostic("action_failed", { "action": action.get_id(), "step": step, "plan_id": get_instance_id(), "reason": "perform_returned_failure" })
	return status


func _stop_action(agent: GoapAgent, reason := "interrupted") -> void:
	if _started:
		_started = false
		# Clear ownership before user cleanup can install/start another action.
		if agent.current_action == actions[step]:
			agent.current_action = null
		if agent.diagnostics_enabled:
			agent.record_diagnostic("action_stopped", { "action": actions[step].get_id(), "step": step, "plan_id": get_instance_id(), "reason": reason })
		actions[step].stop(agent)


func _to_string() -> String:
	return "%s cost:%s" % [actions, cost]
