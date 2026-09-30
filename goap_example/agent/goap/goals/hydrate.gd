extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	if state.get_state(Facts.DEHYDRATED):
		return Priorities.DEHYDRATION
	return Priorities.THIRST if state.get_state(Facts.THIRSTY) else 0.0


func _get_name() -> String:
	return "SatisfyThirst"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({Facts.THIRSTY: false})
