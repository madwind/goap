extends GoapAction


func _get_name() -> StringName:
	return "unarmed_attack"


func get_cost(agent: GoapAgent, state: GoapWorldState) -> float:
	return 10


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_ENEMY: false})


func perform(agent: GoapAgent, delta: float) -> bool:
	return true
