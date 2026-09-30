extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	return Priorities.FIRE if state.get_state(Facts.FIRE_LOW) and state.get_state(Facts.CAN_TEND_FIRE) else 0.0


func _get_name() -> String:
	return "MaintainFire"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({ Facts.FIRE_STABLE: true })
