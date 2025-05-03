extends GoapAction


func _get_name() -> StringName:
	return "MeleeAttack"


func get_cost(agent: GoapAgent, state: GoapWorldState) -> float:
	return 1


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({
		WorldStateKey.HAS_EQUIPPED_WEAPON: true,
		WorldStateKey.HAS_ALLY: true,
		})


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_ENEMY: false})

func perform(agent: GoapAgent, delta: float) -> bool:
	var actor := agent.actor
	var enemies: Array = agent.blackboard.get(BlackboardKey.ENEMY, [])
	if agent.distance_to_target(enemies[0]) > actor.attack_range:
		actor.move_to(enemies[0].global_position)
		return false
	else:
		actor.kill_enemy(enemies[0])
		return true
