extends SceneTree

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("STOW: " + message)


func run() -> void:
	var world = load("res://goap_example/world.tscn").instantiate()
	world.agent_count = 1
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	world.fire_remaining = 1000.0
	var actor = world.actors[0]
	var agent: GoapAgent = actor.get_node("GoapAgent")
	agent.suspend()
	agent.goals = [preload("res://goap_example/agent/goap/goals/stow_supplies.gd").new()]
	actor.satiety = 100.0
	actor.hydration = 100.0
	actor.hunger_rate = 0.0
	actor.thirst_rate = 0.0
	var picked: Array[Node3D] = []
	var stow_goal_seen := false
	for item in [
		preload("res://goap_example/resources/wood.tres"),
		preload("res://goap_example/resources/water.tres"),
	]:
		world.drop_item(item, actor.global_position + Vector3(1, 0, 0))
		var model: Node3D
		for resource in world.resources:
			if resource.item == item and resource.available:
				model = resource
				break
		actor.pick_up(item, model)
		for frame in 180:
			await physics_frame
			if actor.has_item(item.inventory_key):
				break
		check(is_instance_valid(model) and model.get_parent() == actor.get_node("CarriedGoods"),
			"%s is held as its original model" % item.title)
		picked.append(model)
		check(not actor.can_carry_item(), "carrying one item fills the carrying slot")
		agent.resume()
		for frame in 600:
			await physics_frame
			if agent.current_goal != null and agent.current_goal.name == "StowCarriedSupplies":
				stow_goal_seen = true
			if model.stored_at_camp:
				break
		agent.suspend()
		check(model.stored_at_camp and actor.can_carry_item(), "delivery frees the carrying slot")
	check(stow_goal_seen, "GOAP chooses to return carried supplies")
	check(not actor.has_held_goods() and not actor.wood and not actor.water,
		"agent stops carrying wood and water after depositing them")
	check(world.camp_stock_count(&"wood") == 1 and world.camp_stock_count(&"water") == 1,
		"wood and water are stored after separate deliveries")
	for model in picked:
		check(is_instance_valid(model) and model.get_parent() == world and model.stored_at_camp and model.visible,
			"the same picked model remains visible in camp")
	world.queue_free()
	await process_frame
	print("Stow supplies: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _initialize() -> void:
	call_deferred("run")
