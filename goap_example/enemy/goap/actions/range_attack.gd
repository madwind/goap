extends GoapAction


func _get_name() -> StringName:
	return "RangeAttack"


func get_cost(agent: GoapAgent, state: GoapWorldState) -> float:
	return 5


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_EQUIPPED_WEAPON: true})


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_ENEMY: false})
