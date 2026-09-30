extends SceneTree

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CAMP: " + message)


func run() -> void:
	var world = load("res://goap_example/world.tscn").instantiate()
	world.agent_count = 1
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	var actor = world.actors[0]
	actor.get_node("GoapAgent").suspend()
	actor.hunger_rate = 0.0
	actor.thirst_rate = 0.0
	var meat = preload("res://goap_example/resources/raw_meat.tres")
	world.drop_item(meat, actor.global_position + Vector3(2, 0, 0))
	var item: Node3D
	for resource in world.resources:
		if resource.item == meat:
			item = resource
			break
	check(world.get_node_or_null("CampFence") != null, "camp has a visible fence")
	check(item != null, "raw meat exists as a scene object")
	actor._begin_ability(preload("res://goap_example/agent/abilities/replenishing.gd").new(actor, meat))
	var seen_carried := false
	var delivered := false
	for frame in 1200:
		await physics_frame
		if item == null or not is_instance_valid(item):
			break
		if item.in_transit and item.get_parent() == actor.get_node("CarriedGoods"):
			seen_carried = true
		if item.stored_at_camp and item.get_parent() == world:
			delivered = true
			break
	check(seen_carried, "agent carries the original resource object")
	check(delivered, "meat is deposited inside camp")
	if delivered:
		check(item.available and not item.in_transit and world.resources.has(item), "stored resource is available for later use")
		check(item.get_node("Visual/Meat").mesh is SphereMesh and item.get_node("Visual").get_child_count() > 1,
			"stored meat has a distinct visible shape")
		check(item.global_position.distance_to(world.get_node("CampFence/MeatRack").global_position) < 2.5,
			"meat is visibly placed on the camp rack")
		actor.pick_up(meat, item)
		for frame in 600:
			await physics_frame
			if actor.raw_meat:
				break
		check(actor.raw_meat, "an agent can take stored meat for a survival action")
		check(world.camp_stock_count(&"meat") == 0, "taking stored goods removes them from camp stock")
		actor.consume_item(&"raw_meat")
	world.drop_item(meat, actor.global_position + Vector3(1.5, 0, 0))
	var loose_meat: Node3D
	for resource in world.resources:
		if resource.item == meat and not resource.stored_at_camp:
			loose_meat = resource
			break
	actor._begin_ability(preload("res://goap_example/agent/abilities/replenishing.gd").new(actor, meat))
	var carrying_meat := false
	for frame in 600:
		await physics_frame
		if is_instance_valid(loose_meat) and loose_meat.in_transit:
			carrying_meat = true
			break
	check(carrying_meat, "agent starts another physical delivery")
	if carrying_meat:
		actor.take_damage(100)
		check(loose_meat.get_parent() == world and loose_meat.available and not loose_meat.in_transit,
			"interrupted delivery drops the item back into the world")
		check(loose_meat.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"interrupted delivery does not restore item collision")
	check(not world.hud.stats.get_node("Raw").visible, "meat is not displayed as a numeric resource count")
	world.queue_free()
	await process_frame
	print("Camp hauling: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _initialize() -> void:
	call_deferred("run")
