extends SceneTree

const Map = preload("res://goap_example/survival/map.gd")
var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WAREHOUSE: " + message)


func run() -> void:
	var world = load("res://goap_example/world.tscn").instantiate()
	world.agent_count = 1
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	world.fire_remaining = 1000.0
	var actor = world.actors[0]
	var agent: GoapAgent = actor.get_node("GoapAgent")
	agent.goals.assign(agent.goals.filter(func(goal: GoapGoal) -> bool: return goal.name != "CraftCampWeapon"))
	actor.satiety = 100.0
	actor.hydration = 100.0
	actor.hunger_rate = 0.0
	actor.thirst_rate = 0.0
	for item in [
		preload("res://goap_example/resources/wood.tres"),
		preload("res://goap_example/resources/stone_item.tres"),
		preload("res://goap_example/resources/water.tres"),
		preload("res://goap_example/resources/raw_meat.tres"),
	]:
		var amount: int = world.CAMP_STOCK_LIMIT - (1 if item.kind == &"meat" else 0)
		world.drop_item(item, Vector3(0, 0, 0), amount)
		for resource in world.resources.duplicate():
			if resource.item == item and not resource.stored_at_camp:
				world.store_cargo(resource)
	check(not world.stockpile_full() and world.camp_stock_count(&"meat") == world.CAMP_STOCK_LIMIT - 1,
		"warehouse starts one meat short of full")
	var bench: Node3D = world.get_node("CampFence/Workbench")
	for resource in world.resources:
		if not resource.stored_at_camp:
			continue
		check(Map._inside_fence(resource.global_position - world.get_node("Campfire").global_position),
			"stored supplies stay inside the round camp")
		if resource.kind == &"wood" or resource.kind == &"stone_item":
			check(resource.global_position.distance_to(bench.global_position) < 4.2,
				"crafting supplies are stored beside the workbench")
	check(not Map._inside_fence(Vector3(7, 0, 7)) and Map._inside_fence(Vector3(5, 0, 5)),
		"camp membership follows a circle rather than a rectangle")
	check(Map._segment_crosses_fence(Vector3(-12, 0, 0), Vector3(12, 0, 0))
		and not Map._segment_crosses_fence(Vector3(-12, 0, 9), Vector3(12, 0, 9)),
		"routes detect crossings of the circular fence")
	world.drop_item(preload("res://goap_example/resources/raw_meat.tres"), actor.global_position + Vector3(1.5, 0, 0))
	var final_meat: Node3D
	for resource in world.resources:
		if resource.item != null and resource.kind == &"meat" and not resource.stored_at_camp:
			final_meat = resource
			break
	agent.request_replan()
	var goal_started := false
	var delivered := false
	for frame in 1200:
		await physics_frame
		if agent.current_goal != null and agent.current_goal.name == "FillCampStorage" and agent.current_action != null and agent.current_action.get_id().begins_with("Replenish:"):
			goal_started = true
		if world.stockpile_full() and is_instance_valid(final_meat) and final_meat.stored_at_camp:
			delivered = true
			break
	check(goal_started, "GOAP chooses the fill-warehouse goal")
	check(delivered, "GOAP stores the final visible item")
	if delivered:
		check(final_meat.get_parent() == world and final_meat.visible, "the final meat model remains in camp")
	agent.suspend()
	var fence: Node3D = world.get_node("CampFence")
	var collision_sections := 0
	for child in fence.get_children():
		if child is StaticBody3D:
			collision_sections += 1
			check(absf(Vector2(child.position.x, child.position.z).length() - Map.CAMP_FENCE_RADIUS) < 0.05,
				"fence collision sections follow the circular boundary")
	check(collision_sections > 0 and Map.CAMP_FENCE_RADIUS > 6.2,
		"expanded fence sections have collision bodies")
	actor.position = world.get_node("Campfire").position + Vector3(6, 0, 4)
	var wall_steering := {}
	for frame in 24:
		await physics_frame
		Map.move_on_ground(actor, Vector3.RIGHT, actor.movement_speed, wall_steering)
	check(actor.position.x < world.get_node("Campfire").position.x + Map.CAMP_FENCE_RADIUS,
		"a character cannot walk straight through a fence rail")
	actor.position = world.get_node("Campfire").position
	for frame in 600:
		await physics_frame
		actor.move_to(world.get_node("Campfire").position + Vector3(12, 0, 0))
		if actor.position.x > world.get_node("Campfire").position.x + Map.CAMP_FENCE_RADIUS + 0.5:
			break
	check(actor.position.x > world.get_node("Campfire").position.x + Map.CAMP_FENCE_RADIUS + 0.5,
		"agent exits through a fence gate")
	actor.stop_moving()
	for frame in 600:
		await physics_frame
		actor.move_to(world.get_node("Campfire").position)
		if actor.is_at_camp():
			break
	check(actor.is_at_camp(), "agent returns through a fence gate")
	actor.stop_moving()
	actor.position = world.get_node("Campfire").position + Vector3(-12, 0, 0)
	for frame in 1200:
		await physics_frame
		actor.move_to(world.get_node("Campfire").position + Vector3(12, 0, 0))
		if actor.position.x > world.get_node("Campfire").position.x + 10:
			break
	check(actor.position.x > world.get_node("Campfire").position.x + 10,
		"agent can travel from one side of the fenced camp to the other")
	actor.stop_moving()
	actor.position = world.get_node("Campfire").position + Vector3(7, 0, 7)
	for frame in 600:
		await physics_frame
		actor.move_to(world.get_node("Campfire").position)
		if actor.is_at_camp():
			break
	check(actor.is_at_camp(), "agent follows the round fence to enter from a diagonal")
	actor.stop_moving()
	actor.weapon_durability = 0
	var crafting = actor.craft_weapon()
	check(crafting.target == bench, "weapon crafting targets the workbench")
	for frame in 600:
		await physics_frame
		if actor.weapons_crafted > 0:
			break
	check(actor.weapons_crafted > 0 and actor.global_position.distance_to(bench.global_position) < 2.1,
		"agent crafts beside the workbench")
	world.queue_free()
	await process_frame
	print("Warehouse goal: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _initialize() -> void:
	call_deferred("run")
