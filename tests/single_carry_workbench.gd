extends SceneTree

const Execution = preload("res://goap_example/agent/abilities/execution.gd")
const Wood = preload("res://goap_example/resources/wood.tres")
const Stone = preload("res://goap_example/resources/stone_item.tres")
const Water = preload("res://goap_example/resources/water.tres")
var checks := 0
var failures := 0
var world: Node3D


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CARRY WORKBENCH: " + message)


func create_item(definition: Resource, stored := false) -> Node3D:
	world.drop_item(definition, Vector3.ZERO)
	var model: Node3D = world.resources.back()
	if stored:
		world.store_cargo(model)
	return model


func run() -> void:
	world = load("res://goap_example/world.tscn").instantiate()
	world.agent_count = 2
	world.random_resources = false
	root.add_child(world)
	world.fire_remaining = 1000.0
	world.monster_spawn_clock = 1000.0
	for resource in world.resources:
		resource.available = false
		resource.set_physics_process(false)
	for actor in world.actors:
		actor.get_node("GoapAgent").suspend()
		actor.hunger_rate = 0.0
		actor.thirst_rate = 0.0
		actor.satiety = 100.0
		actor.hydration = 100.0
	var actor = world.actors[0]
	var rival = world.actors[1]
	var bench: Node3D = world.get_node("CampFence/Workbench")
	var timber := create_item(Wood)
	var stone := create_item(Stone, true)
	check(actor.take_item_model(timber) and not actor.can_carry_item(), "one wood model fills the carrying slot")
	check(not actor.take_item_model(stone) and stone.stored_at_camp and world.camp_stock_count(&"stone_item") == 1,
		"full hands cannot take another kind of item or remove it from storage")
	var pickup = actor.pick_up(Stone, stone)
	check(pickup.state == Execution.State.FAILED and timber.get_parent() == actor.get_node("CarriedGoods"),
		"pickup ability rejects a second item and retains the original model")
	var delivery := preload("res://goap_example/agent/goap/parameterized/replenish.gd").new()
	delivery.configure(Stone)
	check(not delivery.is_valid(actor.get_node("GoapAgent")), "full hands cannot start a different supply delivery")
	actor.position = bench.global_position
	var missing = actor.craft_weapon()
	missing.advance(2.1)
	check(missing.state == Execution.State.FAILED and actor.weapon_durability == 0,
		"held wood does not substitute for missing camp stock")
	check(actor.wood and world.camp_stock_count(&"stone_item") == 1 and not stone.is_queued_for_deletion(),
		"a missing recipe ingredient consumes neither held goods nor stored stone")
	actor.deposit_item()
	check(actor.can_carry_item() and world.has_crafting_materials(), "deposit frees the hands and enables the camp recipe")
	var water := create_item(Water)
	check(actor.take_item_model(water), "a free carrying slot can take the next item")
	actor.position = bench.global_position + Vector3(12, 0, 0)
	var travelling = actor.craft_weapon()
	travelling.advance(2.1)
	check(travelling.target == bench and travelling.elapsed == 0.0 and actor.weapon_durability == 0,
		"crafting travels to the workbench before making any progress")
	check(not actor.finish_weapon() and world.camp_stock_count(&"wood") == 1 and world.camp_stock_count(&"stone_item") == 1,
		"calling completion away from the workbench cannot spend camp materials")
	travelling.cancel()
	actor.position = bench.global_position + Vector3(0.5, 0, 0)
	rival.position = bench.global_position - Vector3(0.5, 0, 0)
	var first = actor.craft_weapon()
	var second = rival.craft_weapon()
	first.advance(0.5)
	check(world.camp_stock_count(&"wood") == 1 and world.camp_stock_count(&"stone_item") == 1,
		"starting work does not consume materials before completion")
	first.advance(1.6)
	second.advance(2.1)
	check(first.state == Execution.State.SUCCEEDED and second.state == Execution.State.FAILED,
		"two crafters cannot spend the same pair of materials")
	check(actor.weapons_crafted == 1 and rival.weapons_crafted == 0 and rival.weapon_durability == 0,
		"only the successful crafter receives a weapon")
	check(world.camp_stock_count(&"wood") == 0 and world.camp_stock_count(&"stone_item") == 0
		and timber.is_queued_for_deletion() and stone.is_queued_for_deletion(),
		"one completed weapon consumes exactly one wood and one stone model")
	check(actor.water and water.get_parent() == actor.get_node("CarriedGoods") and actor.carried_item == water,
		"crafting uses camp stock and leaves the single carried item intact")
	check(not actor.finish_weapon(), "an equipped actor cannot craft a duplicate weapon")
	actor.weapon_durability = 0
	var replacement_wood := create_item(Wood, true)
	check(not actor.finish_weapon() and world.camp_stock_count(&"wood") == 1 and not replacement_wood.is_queued_for_deletion(),
		"missing stone cannot partially consume the next recipe")
	var replacement_stone := create_item(Stone, true)
	var cancelled = actor.craft_weapon()
	cancelled.advance(0.5)
	cancelled.cancel()
	check(world.camp_stock_count(&"wood") == 1 and world.camp_stock_count(&"stone_item") == 1
		and not replacement_wood.is_queued_for_deletion() and not replacement_stone.is_queued_for_deletion(),
		"cancelling a craft preserves both ingredients")
	actor.consume_item(&"water")
	var agent: GoapAgent = actor.get_node("GoapAgent")
	agent.goals = [preload("res://goap_example/agent/goap/goals/equip.gd").new()]
	agent.resume()
	var goal_seen := false
	for frame in 600:
		await physics_frame
		if agent.current_goal != null and agent.current_goal.name == "CraftCampWeapon":
			goal_seen = true
		if actor.weapons_crafted == 2:
			break
	check(goal_seen and actor.weapons_crafted == 2, "camp stock autonomously triggers workbench crafting")
	check(world.camp_stock_count(&"wood") == 0 and world.camp_stock_count(&"stone_item") == 0,
		"autonomous crafting also consumes one of each stored ingredient")
	world.queue_free()
	await process_frame
	print("Single carry and workbench: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
