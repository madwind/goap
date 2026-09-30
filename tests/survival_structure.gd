extends SceneTree

const Wood = preload("res://goap_example/resources/wood.tres")
const Stone = preload("res://goap_example/resources/stone_item.tres")
const Execution = preload("res://goap_example/agent/abilities/execution.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")
var checks := 0
var failures := 0
var world: Node3D


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SURVIVAL STRUCTURE: " + message)


func item(definition: Resource, stored := false) -> Node3D:
	world.drop_item(definition, Vector3.ZERO)
	var model: Node3D = world.resources.back()
	if stored:
		world.store_cargo(model)
	return model


func run() -> void:
	world = preload("res://goap_example/world.tscn").instantiate()
	world.agent_count = 3
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	var camp: Node3D = world.get_node("Campfire")
	for index in world.actors.size():
		var actor: Node3D = world.actors[index]
		actor.get_node("GoapAgent").set_physics_process(false)
		actor.set_physics_process(false)
		actor.hunger_rate = 0.0
		actor.thirst_rate = 0.0
		actor.satiety = 100.0
		actor.hydration = 100.0
		actor.position = camp.position + Vector3(0.5 + index, 0, 0)
	var first: Node3D = world.actors[0]
	var second: Node3D = world.actors[1]
	var third: Node3D = world.actors[2]
	var first_wood := item(Wood)
	var second_wood := item(Wood)
	first.take_item_model(first_wood)
	second.take_item_model(second_wood)
	await physics_frame
	await physics_frame
	check(camp.can_tend_fire(first) and not camp.can_tend_fire(second), "the camp nominates one fire tender")
	var nomination: WeakRef = camp._fire_tender
	var timer: float = camp.fire_remaining
	var recovering: bool = first.recovering
	first.health = 5
	for repetition in 10:
		first.get_node("GoapAgent").refresh_world_state()
	check(first.recovering == recovering and camp._fire_tender == nomination and camp.fire_remaining == timer,
		"observations do not change health hysteresis, fire assignment or the timer")
	first.health = 20
	var lighting = first.light_fire()
	var replacement = first.light_fire()
	check(lighting.state == Execution.State.CANCELLED and replacement.state == Execution.State.RUNNING,
		"replacing an ability releases its claim before the next ability claims it")
	check(second.light_fire().state == Execution.State.FAILED, "a peer cannot start another lighting operation")
	check(first.carried_item == first_wood and second.carried_item == second_wood, "failed and cancelled lighting preserves both models")
	first.take_damage(100)
	check(first_wood.get_parent() == world and first_wood.available and not first_wood.in_transit,
		"death drops the original single carried item")
	await physics_frame
	await physics_frame
	check(camp.can_tend_fire(second), "a dead tender releases the role for a living peer")
	var handoff = second.light_fire()
	handoff.advance(1.1)
	check(handoff.state == Execution.State.SUCCEEDED and camp.has_stable_fire() and second.can_carry_item(),
		"the replacement tender completes lighting and consumes its own wood")
	check(first_wood.available and second_wood.is_queued_for_deletion(), "handoff spends only the replacement tender's wood")
	var stored_stone := item(Stone, true)
	var stored_wood := item(Wood, true)
	var agent: GoapAgent = third.get_node("GoapAgent")
	agent.refresh_world_state()
	var sources := GoapWorldStateProvider.discover(world, agent)
	var contributors := 0
	for provider in sources:
		if provider.get_world_state(agent).has_state(Facts.CAMP_HAS_WOOD):
			contributors += 1
	check(contributors == 1 and agent.world_state.get_state(Facts.CAMP_HAS_WOOD), "only the camp provider publishes shared inventory")
	third.take_item_model(stored_wood)
	agent.refresh_world_state()
	check(not agent.world_state.get_state(Facts.CAMP_HAS_WOOD) and agent.world_state.get_state(Facts.HAS_WOOD),
		"taking camp stock moves the fact from shared storage to the single carry slot")
	world.set_agent_count(2)
	check(stored_wood.get_parent() == world and stored_wood.available and not stored_wood.stored_at_camp,
		"population removal returns a carried model to the world")
	stored_stone.queue_free()
	agent = second.get_node("GoapAgent")
	agent.refresh_world_state()
	check(not agent.world_state.get_state(Facts.CAMP_HAS_STONE) and not camp.has_crafting_materials(),
		"queued removal cannot leave phantom stock or enable a recipe")
	world.queue_free()
	await process_frame
	print("Survival structure: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
