class_name GoapPlanningWork
extends RefCounted
## Only snapshot data and audited immutable GDScript code handles enter here.
## Continuation objects are constructed locally and owned exclusively by the
## executing thread until the task is joined. Output contains data only.


static func begin(
	world: Dictionary[StringName, bool],
	goal_state: Dictionary[StringName, bool],
	prepared: Dictionary,
	models: Array,
	cost_state: Dictionary,
	limit: int,
	debug: bool,
	capture_comparisons: bool = false
) -> Dictionary:
	return {
		"search": GoapSearch.begin(world, goal_state, prepared, limit, debug),
		"world": world,
		"goal_state": goal_state,
		"models": models,
		"cost_state": cost_state,
		"capture_comparisons": capture_comparisons,
		"phase": GoapPlanningData.Phase.SEARCHING,
		"evaluation": null,
		"result": {}
	}


static func advance(work: Dictionary, deadline_usec: int = 0) -> bool:
	while work.phase != GoapPlanningData.Phase.COMPLETED and (
		deadline_usec == 0 or Time.get_ticks_usec() < deadline_usec
	):
		match work.phase:
			GoapPlanningData.Phase.SEARCHING:
				if GoapSearch.advance(work.search, deadline_usec):
					work.evaluation = GoapEvaluation.new(
						GoapSearch.result(work.search),
						work.search.prepared.records,
						work.world,
						work.goal_state,
						work.cost_state,
						work.models,
						work.capture_comparisons
					)
					work.phase = GoapPlanningData.Phase.EVALUATING
			GoapPlanningData.Phase.EVALUATING:
				var evaluation: GoapEvaluation = work.evaluation
				if evaluation.advance(deadline_usec):
					evaluation.statistics.evaluation_on_worker = OS.get_thread_caller_id() != OS.get_main_thread_id()
					work.result = GoapPlanningData.evaluation_result(evaluation)
					work.evaluation = null
					work.phase = GoapPlanningData.Phase.COMPLETED
	return work.phase == GoapPlanningData.Phase.COMPLETED


## Run on main thread only after joining the task; map indexes back to the same request's live actions.
static func materialize(result: Dictionary, planner: GoapPlanner) -> GoapPlan:
	planner.statistics = result.statistics.duplicate(true)
	if not result.warnings.is_empty():
		planner.statistics.warnings = result.warnings.duplicate()
	planner.search_tree = result.trace
	for warning: String in result.warnings:
		GoapPlanningSafety.warn(warning)
	if not result.found:
		return null
	var plan := GoapPlan.new()
	for index: int in result.action_indices:
		plan.actions.append(planner.actions[index])
	plan.cost = planner.statistics.cost
	plan.planning_time_ms = planner.statistics.planning_time_ms
	plan.expanded_nodes = planner.statistics.expanded_nodes
	plan.pruned_nodes = planner.statistics.pruned_nodes
	plan.search_complete = planner.statistics.search_complete
	return plan
