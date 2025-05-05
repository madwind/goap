extends GoapAction


func _get_name() -> StringName:
	return "Alert"


func get_cost(_agent: GoapAgent, _state: GoapWorldState) -> float:
	return 1.0


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_ALLY: true})


func perform(agent: GoapAgent, delta: float) -> bool:
	return true
