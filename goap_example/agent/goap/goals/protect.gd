extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	return Priorities.DEFENSE if is_valid(state) and state.get_state(Facts.HAS_MONSTER) else 0.0


func is_valid(state: GoapWorldState) -> bool:
	return not state.get_state(Facts.LOW_HEALTH) and not state.get_state(Facts.STARVING) and not state.get_state(Facts.DEHYDRATED)


func _get_name() -> String:
	return "DefendFromMonster"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HAS_MONSTER: false })
