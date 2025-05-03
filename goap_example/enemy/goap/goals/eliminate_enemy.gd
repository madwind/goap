extends GoapGoal


func _get_name() -> String:
	return "EliminateEnemyGoal"


func is_valid(state: GoapWorldState) -> bool:
	return state.get_state(WorldStateKey.HAS_ENEMY, false)


func get_priority() -> int:
	return 1


func _get_desired_state() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_ENEMY: false})
