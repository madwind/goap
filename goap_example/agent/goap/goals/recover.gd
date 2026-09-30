extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	return Priorities.RECOVERY if state.get_state(Facts.LOW_HEALTH) else 0.0


func _get_name() -> String:
	return "RecoverHealth"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({ Facts.LOW_HEALTH: false })
