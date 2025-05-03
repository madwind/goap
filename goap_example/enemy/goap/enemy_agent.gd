extends GoapAgent


func _init_world_state() -> void:
	world_state.merge(GoapWorldState.new({
		WorldStateKey.HAS_ALLY: false,
		WorldStateKey.HAS_ENEMY: false,
		WorldStateKey.HAS_EQUIPPED_WEAPON: false,
		WorldStateKey.HAS_WEAPON: false
	}))


func _on_target_changed(body: Node3D) -> void:
	if body.is_in_group("player"):
		var enemies: Array = blackboard.get_or_add(BlackboardKey.ENEMY, [])
		if not enemies.has(body):
			enemies.append(body)
			world_state.set_state(WorldStateKey.HAS_ENEMY, true)

	if body.is_in_group("weapon"):
		var weapons: Array = blackboard.get_or_add(BlackboardKey.WEAPON, [])
		if not weapons.has(body):
			weapons.append(body)
			world_state.set_state(WorldStateKey.HAS_WEAPON, true)


func goto(target: Node3D) -> void:
	navigation_agent.target_position = target.global_position
	var next_path_position := navigation_agent.get_next_path_position()
	actor.move_to(next_path_position)
