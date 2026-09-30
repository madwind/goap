extends SceneTree

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PICKUP: " + message)


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
	for item in [
		preload("res://goap_example/resources/wood.tres"),
		preload("res://goap_example/resources/water.tres"),
		preload("res://goap_example/resources/stone_item.tres"),
		preload("res://goap_example/resources/raw_meat.tres"),
	]:
		world.drop_item(item, actor.global_position + Vector3(1, 0, 0))
		var model: Node3D
		for resource in world.resources:
			if resource.item == item and resource.available and not resource.stored_at_camp:
				model = resource
				break
		check(model != null, "%s starts as a ground model" % item.title)
		check(model != null and model.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"%s ground model has no physics collider" % item.title)
		actor.pick_up(item, model)
		for frame in 180:
			await physics_frame
			if actor.has_item(item.inventory_key):
				break
		check(actor.has_item(item.inventory_key) and is_instance_valid(model)
			and not model.is_queued_for_deletion() and model.get_parent() == actor.get_node("CarriedGoods")
			and model.visible, "%s pickup keeps the original visible model" % item.title)
		if item.inventory_key == &"raw_meat":
			actor.cook_carried_meat()
			check(actor.cooked_meat and model.kind == &"cooked_meat" and model.get_parent() == actor.get_node("CarriedGoods"),
				"cooking changes the carried meat model")
			actor.eat(true)
			check(not actor.cooked_meat and model.is_queued_for_deletion(), "eating removes the model only when consumed")
		elif item.inventory_key == &"water":
			actor.drink()
			check(not actor.water and model.is_queued_for_deletion(), "drinking consumes the water model")
		else:
			actor.consume_item(item.inventory_key)
			check(model.is_queued_for_deletion(), "%s model is removed when used" % item.title)
		await process_frame
	world.queue_free()
	await process_frame
	print("Physical pickups: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _initialize() -> void:
	call_deferred("run")
