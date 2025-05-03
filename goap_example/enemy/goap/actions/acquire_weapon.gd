extends GoapAction


func _get_name() -> StringName:
	return "AcquireWeapon"


func is_valid(agent: GoapAgent) -> bool:
	if agent.world_state.get_state(WorldStateKey.HAS_WEAPON):
		var weapons: Array = agent.blackboard.get(BlackboardKey.WEAPON, [])
		return weapons and weapons.size() > 0
	return false


func get_cost(agent: GoapAgent, state: GoapWorldState) -> float:
	var cost := 1.0
	var weapons: Array = agent.blackboard.get(BlackboardKey.WEAPON, [])
	if weapons.size() == 0:
		return 1000.0
	cost += agent.distance_to_target(weapons[0]) * 0.1
	return cost


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_WEAPON: true})


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({WorldStateKey.HAS_EQUIPPED_WEAPON: true})


func perform(agent: GoapAgent, delta: float) -> bool:
	var actor := agent.actor
	var weapons: Array = agent.blackboard.get(BlackboardKey.WEAPON, [])
	if agent.distance_to_target(weapons[0]) > actor.weapon_pickup_range:
		actor.move_to(weapons[0].global_position)
		return false
	else:
		actor.pickup_item(weapons[0])
		return true
