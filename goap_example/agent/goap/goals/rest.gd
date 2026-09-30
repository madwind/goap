extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	return Priorities.REST if state.get_state(Facts.NEEDS_REST) else 0.0


func _get_name() -> String:
	return "RestAtCamp"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({ Facts.AT_CAMP: true })
