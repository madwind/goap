extends GoapAction


func get_name() -> StringName:
	return "Feed"


func get_cost(_agent: GoapAgent, _state: GoapWorldState) -> float:
	return 1


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new()


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new()
