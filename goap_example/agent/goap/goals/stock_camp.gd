extends GoapGoal

const Priorities = preload("res://goap_example/agent/goap/priorities.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_priority(state: GoapWorldState) -> float:
	if state.get_state(Facts.STOCKPILE_FULL) or state.get_state(Facts.HUNGRY) or state.get_state(Facts.THIRSTY) or state.get_state(Facts.LOW_HEALTH) or state.get_state(Facts.HAS_MONSTER):
		return 0.0
	return Priorities.STOCK


func _get_name() -> String:
	return "FillCampStorage"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new({ Facts.STOCKPILE_FULL: true })
