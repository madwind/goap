extends SceneTree

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("REPLENISHMENT: " + message)


func run() -> void:
	seed(928)
	var world = preload("res://goap_example/world.tscn").instantiate()
	world.agent_count = 2
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	world.fire_remaining = 1000.0
	var camp: Node3D = world.get_node("Campfire")
	for actor in world.actors:
		actor.satiety = 100.0
		actor.hydration = 100.0
		actor.hunger_rate = 0.0
		actor.thirst_rate = 0.0
		actor.movement_speed = 12.0
		var agent: GoapAgent = actor.get_node("GoapAgent")
		agent.asynchronous_planning = false
		agent.goals.assign(agent.goals.filter(func(goal: GoapGoal) -> bool:
			return goal.name in ["FillCampStorage", "StowCarriedSupplies"]
		))
	check(camp.STOCK_KINDS.all(func(kind: StringName) -> bool: return camp.stock_count(kind) == 0), "all four stocks start empty")
	var saw_harvest := false
	var saw_carry := false
	for frame in 24000:
		await physics_frame
		for actor in world.actors:
			var operation = actor._active_ability
			saw_harvest = saw_harvest or operation != null and operation.label.begins_with("Harvest")
			saw_carry = saw_carry or actor.has_held_goods()
		if camp.stockpile_full():
			break
	check(saw_harvest and saw_carry, "GOAP replenishment harvests sources and carries their physical drops")
	check(camp.stockpile_full(), "two agents can refill an empty camp without an actor hauling loop")
	for kind in camp.STOCK_KINDS:
		check(camp.stock_count(kind) >= camp.STOCK_LIMIT, "%s reaches its stock target" % kind)
	for actor in world.actors:
		check(actor.get_node("CarriedGoods").get_child_count() <= 1, "every delivery respects the single carrying slot")
	world.queue_free()
	await process_frame
	print("Camp replenishment: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
