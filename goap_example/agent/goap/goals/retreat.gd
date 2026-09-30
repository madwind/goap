extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	return Priorities.ESCAPE if state.get_state(Facts.LOW_HEALTH) and state.get_state(Facts.IN_DANGER) else 0.0


func _get_name() -> String:
	return "ReachSafety"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({ Facts.IN_DANGER: false })
