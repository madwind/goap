extends SceneTree

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FIRE HAUL: " + message)


func run() -> void:
	var world = load("res://goap_example/world.tscn").instantiate()
	world.agent_count = 3
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	world.fire_remaining = 1000.0
	for resource in world.resources:
		resource.available = false
		resource.set_physics_process(false)
	var cargo: Array[Node3D] = []
	var definitions := [
		preload("res://goap_example/resources/wood.tres"),
		preload("res://goap_example/resources/stone_item.tres"),
		preload("res://goap_example/resources/water.tres"),
	]
	for index in world.actors.size():
		var actor = world.actors[index]
		actor.get_node("GoapAgent").suspend()
		var agent: GoapAgent = actor.get_node("GoapAgent")
		agent.goals.assign(agent.goals.filter(func(goal: GoapGoal) -> bool: return goal.name in ["FillCampStorage", "MaintainFire"]))
		actor.position = world.get_node("Campfire").position + Vector3(12, 0, index * 5)
		actor.satiety = 100.0
		actor.hydration = 100.0
		actor.hunger_rate = 0.0
		actor.thirst_rate = 0.0
		world.drop_item(definitions[index], actor.global_position + Vector3(0.5, 0, 0))
		for resource in world.resources:
			if resource.item == definitions[index]:
				cargo.append(resource)
				actor.take_item_model(resource)
				break
	for index in world.actors.size():
		var actor = world.actors[index]
		check(actor.carried_item == cargo[index] and cargo[index].get_parent() == actor.get_node("CarriedGoods"),
			"each actor starts with the original cargo on a delivery")
		check(actor.has_held_goods(), "all delivery cargo uses the single carrying slot")
	for actor in world.actors:
		actor.get_node("GoapAgent").resume()
	for frame in 180:
		await physics_frame
		if world.actors.all(func(actor: Node3D) -> bool:
			var action: GoapAction = actor.get_node("GoapAgent").current_action
			return action != null and action.get_id().begins_with("Replenish:")
		):
			break
	check(world.actors.all(func(actor: Node3D) -> bool:
		var action: GoapAction = actor.get_node("GoapAgent").current_action
		return action != null and action.get_id().begins_with("Replenish:") and actor.carried_item != null
	), "all actors are actively executing GOAP deliveries before the fire goes out")
	var ongoing: Array = [world.actors[1]._active_ability, world.actors[2]._active_ability]
	world.fire_remaining = 0.0
	var dropped := false
	var lit := false
	var maintenance_seen := false
	var restarted := false
	for frame in 1800:
		await physics_frame
		for model in cargo:
			if is_instance_valid(model) and not model.is_queued_for_deletion():
				if model.get_parent() == world and model.available and not model.stored_at_camp:
					dropped = true
		for actor in world.actors:
			var agent: GoapAgent = actor.get_node("GoapAgent")
			if agent.current_goal != null and agent.current_goal.name == "MaintainFire":
				maintenance_seen = true
		for index in [1, 2]:
			if not cargo[index].stored_at_camp and world.actors[index]._active_ability != ongoing[index - 1]:
				restarted = true
		lit = lit or world.fire_remaining > 0.0
		if lit and cargo[1].stored_at_camp and cargo[2].stored_at_camp:
			break
	check(maintenance_seen and lit, "fire maintenance preempts hauling and relights the camp")
	check(not dropped, "no carried item is dropped during fire-related task changes")
	check(not restarted, "other actors keep the same running delivery through fire state changes")
	check(not is_instance_valid(cargo[0]) or cargo[0].is_queued_for_deletion(),
		"the fire consumes the wood already carried by its lighter")
	for index in [1, 2]:
		check(is_instance_valid(cargo[index]) and cargo[index].stored_at_camp and cargo[index].get_parent() == world,
			"other cargo reaches storage as its original object")

	# A full carrying slot rejects a second item without disturbing either model.
	var actor = world.actors[0]
	actor.get_node("GoapAgent").suspend()
	actor.set_physics_process(false)
	actor.deposit_item()
	world.drop_item(definitions[2], actor.global_position, 2)
	var duplicate: Array[Node3D] = []
	for resource in world.resources:
		if resource.item == definitions[2] and not resource.stored_at_camp:
			duplicate.append(resource)
	check(duplicate.size() == 2, "two water models exist for duplicate cargo interruption")
	if duplicate.size() == 2:
		check(actor.take_item_model(duplicate[0]) and not actor.take_item_model(duplicate[1]),
			"the actor can only pick up one item")
		actor.rest_at_camp().cancel()
		check(actor.carried_item == duplicate[0] and duplicate[1].get_parent() == world and duplicate[1].available,
			"interruption retains the held item and leaves the rejected item on the ground")
		actor.deposit_item()
		check(duplicate[0].stored_at_camp and not duplicate[1].stored_at_camp and actor.can_carry_item(),
			"deposit stores exactly the single carried item")
	world.queue_free()
	await process_frame
	print("Fire haul interruption: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
