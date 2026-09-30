class_name GoapPlanningData
extends RefCounted
## Internal dictionary contract for worker continuations.
## have exclusive thread ownership; only reports expose phase names as strings.

enum Phase {
	PREPARING,
	SEARCHING,
	EVALUATING,
	COMPLETED,
}


static func phase_name(phase: Phase) -> String:
	match phase:
		Phase.PREPARING: return "preparing"
		Phase.SEARCHING: return "searching"
		Phase.EVALUATING: return "evaluating"
		Phase.COMPLETED: return "completed"
	return ""


static func search_statistics() -> Dictionary:
	return {
		"expanded_nodes": 0,
		"pruned_nodes": 0,
		"candidate_count": 0,
		"search_complete": false,
		"planning_time_ms": 0.0,
		"preparation_time_ms": 0.0,
		"search_time_ms": 0.0,
		"evaluation_time_ms": 0.0,
		"prune_reasons": {}
	}


static func evaluation_result(evaluation: GoapEvaluation) -> Dictionary:
	return {
		"found": evaluation.found,
		"action_indices": evaluation.best_action_indices,
		"statistics": evaluation.statistics,
		"trace": evaluation.search_result.trace,
		"warnings": evaluation.warnings
	}
