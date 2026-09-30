extends SceneTree

const Balance = preload("res://goap_example/survival/balance.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")
const Execution = preload("res://goap_example/agent/abilities/execution.gd")

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("EXAMPLE: " + message)


func until(predicate: Callable, frames := 1200) -> bool:
	for frame in frames:
		await physics_frame
		if predicate.call():
			return true
	return false


func run() -> void:
	var world = load("res://goap_example/world.tscn").instantiate()
	world.agent_count = 1
	world.random_resources = false
	root.add_child(world)
	world.monster_spawn_clock = 1000.0
	var actor = world.actors[0]
	var agent: GoapAgent = actor.get_node("GoapAgent")
	check(world.get_node_or_null("Player") == null, "player is absent from the survival scene")
	check(world.get_node_or_null("Groups") == null and world.hud.get_node_or_null("Root/Toolbar/GroupMode") == null,
		"manual group controls are absent")
	check(world.resources.size() == 4, "each agent has one source of each resource")
	check(actor.health == 20, "agent starts at full health")
	var compared: bool = await until(func() -> bool:
		return agent.current_plan != null and preload("res://goap_example/agent/goap/plan_explanation.gd").matches_current_plan(agent, agent.planning_statistics)
	, 2400)
	check(compared, "selected agent captures the actual candidate comparison")
	if compared:
		world.hud.update_world(world)
		var explanation: String = preload("res://goap_example/agent/goap/plan_explanation.gd").describe(agent, agent.planning_statistics)
		check(explanation.contains("SELECTED ROUTE")
			and explanation.contains("OTHER ROUTES")
			and explanation.contains("Est. Action cost ")
			and not explanation.contains("Est. Move "),
			"planner diagnostics describe the selected route and alternatives")
	check(world.hud.pause_button.get_parent() == world.hud.get_node("Root/Toolbar"), "pause control stays in the game toolbar")
	check(world.hud.get_node_or_null("RuntimeWindow/RuntimePanel/Column/Tabs/Agent/Sidebar/Column/Body/Execution/Plan") == null,
		"activity has no separate panel above the plan")
	if agent.current_plan != null and agent.current_plan.step < agent.current_plan.actions.size():
		var current_step: String = "%d. %s" % [agent.current_plan.step + 1, agent.current_plan.actions[agent.current_plan.step].name]
		var steps_text: String = world.hud.steps_label.text
		check(steps_text.contains(current_step)
			and not steps_text.contains("Target  ")
			and not steps_text.contains("Position  ")
			and not steps_text.contains("Activity  "),
			"plan steps show actions without target and position details")
	world.hud.pause_button.pressed.emit()
	check(paused and world.hud.pause_button.text == "Resume", "toolbar pauses the simulation")
	world.hud.pause_button.pressed.emit()
	check(not paused and world.hud.pause_button.text == "Pause", "toolbar resumes the simulation")
	check(await until(func() -> bool: return actor.meals > 0, 3600), "agent autonomously finds food")
	check(await until(func() -> bool: return actor.drinks > 0, 6000), "spring and drinking plan restore thirst")
	agent.suspend()
	actor.deposit_item()
	var monster = world.spawn_monster()
	actor.health = 10
	actor.position = Vector3(4, 0, 12)
	monster.position = actor.position - Vector3(2, 0, 0)
	# Give the fleeing actor one attack interval; recovery is tested under pursuit.
	monster.attack_clock = Balance.MONSTER_ATTACK_SECONDS
	actor.satiety = 100
	actor.hydration = 100
	actor.hunger_rate = 0.0
	actor.thirst_rate = 0.0
	actor.hungry = false
	actor.thirsty = false
	world.drop_item(preload("res://goap_example/resources/cooked_meat.tres"), actor.global_position)
	for resource in world.resources:
		if resource.kind == &"cooked_meat" and resource.available:
			actor.take_item_model(resource)
			break
	agent.resume()
	agent.request_replan()
	check(await until(func() -> bool:
		return (agent.current_goal != null and agent.current_goal.name == "ReachSafety"
			and agent.current_plan != null and agent.current_plan.actions[0].name == &"FleeMonster")
	, 600), "low health near a monster selects fleeing")
	var initial_monster_distance: float = actor.global_position.distance_to(monster.global_position)
	var initial_camp_distance: float = actor.global_position.distance_to(world.get_node("Campfire").global_position)
	check(await until(func() -> bool:
		return (actor.global_position.distance_to(monster.global_position) > initial_monster_distance + 2.0
			and actor.global_position.distance_to(world.get_node("Campfire").global_position) > initial_camp_distance + 1.0)
	, 300), "fleeing moves away from the monster even when camp is behind the actor")
	check(actor.health <= 10, "fleeing does not heal the actor")
	check(await until(func() -> bool:
		return not actor.is_at_camp() and actor.global_position.distance_to(monster.global_position) >= Balance.FLEE_END_RADIUS
	, 600), "fleeing escapes the monster without reaching camp")
	var meals_before: int = actor.meals
	var recovered: bool = await until(func() -> bool: return actor.health >= 16 and actor.meals > meals_before, 3600)
	check(recovered, "agent eats to heal after fleeing")
	check(monster.health == Balance.MONSTER_HEALTH, "fleeing does not attack the monster")
	world.queue_free()
	await process_frame
	var route_world = load("res://goap_example/world.tscn").instantiate()
	route_world.agent_count = 1
	route_world.random_resources = false
	root.add_child(route_world)
	route_world.monster_spawn_clock = 1000.0
	var route_actor = route_world.actors[0]
	var route_agent: GoapAgent = route_actor.get_node("GoapAgent")
	route_agent.suspend()
	route_actor.position = Vector3.ZERO
	route_actor.thirsty = true
	route_actor.hydration = 10
	for resource in route_world.resources:
		if resource.kind == &"spring":
			resource.position = Vector3(3, 0, 0)
	var far_water_position := Vector3(24, 0, 20)
	route_world.drop_item(preload("res://goap_example/resources/water.tres"), far_water_position, 1)
	route_agent.refresh_world_state()
	var water_fact: StringName = preload("res://goap_example/resources/water.tres").available_fact()
	check(route_agent.world_state.get_state(water_fact),
		"distant ground water remains visible when a spring is nearby")
	var route_planner := GoapPlanner.new(route_agent.actions)
	var water_goal := GoapWorldState.new({Facts.THIRSTY: false})
	var far_plan: GoapPlan = route_planner.find_plan(
		route_agent.world_state, water_goal, route_agent.capture_cost_state()
	)
	check(far_plan != null and far_plan.actions.size() >= 2
		and far_plan.actions[0].get_id().begins_with("PickUp:"),
		"an idle agent can plan to collect available ground water")
	var water_drop: Node3D
	for resource in route_world.resources:
		if resource.item != null and resource.item.available_fact() == water_fact:
			water_drop = resource
			break
	if water_drop != null:
		water_drop.position = Vector3(1, 0, 0)
		route_agent.refresh_world_state()
		var direct_plan: GoapPlan = route_planner.find_plan(
			route_agent.world_state, water_goal, route_agent.capture_cost_state()
		)
		check(direct_plan != null and far_plan != null and direct_plan.cost == far_plan.cost
			and direct_plan.actions[0].get_id().begins_with("PickUp:"),
			"moving the water closer keeps the pickup plan")
	var animal: Node3D
	for resource in route_world.resources:
		if resource.kind == &"animal":
			animal = resource
			break
	if animal != null:
		animal.position = Vector3(3, 0, 0)
		animal.home = animal.position
		var farther_animal: Node3D = preload("res://goap_example/resources/animal.tscn").instantiate()
		farther_animal.position = Vector3(18, 0, 0)
		route_world.add_child(farther_animal)
		animal.available = false
		route_agent.refresh_world_state()
		check(route_agent.world_state.get_state(animal.harvest_available_fact()),
			"a depleted nearby animal cannot hide a usable farther animal")
		animal.available = true
		farther_animal.queue_free()
		var meat_item = preload("res://goap_example/resources/raw_meat.tres")
		route_world.drop_item(meat_item, Vector3(25, 0, 0), 1)
		var meat_drop: Node3D
		for resource in route_world.resources:
			if resource.item != null and resource.item.signature() == meat_item.signature():
				meat_drop = resource
				break
		route_agent.refresh_world_state()
		var meat_goal := GoapWorldState.new({Facts.HAS_RAW_MEAT: true})
		var far_meat_plan: GoapPlan = route_planner.find_plan(route_agent.world_state, meat_goal)
		check(route_agent.current_action == null
			and route_agent.world_state.get_state(meat_item.available_fact())
			and far_meat_plan != null and far_meat_plan.actions[0].get_id().begins_with("PickUp:"),
			"an idle agent plans to pick up ground meat even when an animal is closer")
		if meat_drop != null:
			meat_drop.position = Vector3(1, 0, 0)
			route_agent.refresh_world_state()
			var near_meat_plan: GoapPlan = route_planner.find_plan(route_agent.world_state, meat_goal)
			check(route_agent.world_state.get_state(meat_item.available_fact())
				and near_meat_plan != null and near_meat_plan.actions[0].get_id().begins_with("PickUp:"),
				"nearby meat is picked up directly")
			meat_drop.position = Vector3(25, 0, 0)
			animal.available = false
			route_agent.refresh_world_state()
			var only_meat_plan: GoapPlan = route_planner.find_plan(route_agent.world_state, meat_goal)
			check(route_agent.world_state.get_state(meat_item.available_fact())
				and only_meat_plan != null and only_meat_plan.actions[0].get_id().begins_with("PickUp:"),
				"distant meat remains usable when no animal is available")
			animal.available = true
			var saved_goals: Array[GoapGoal] = route_agent.goals.duplicate()
			var meat_acquisition_goal := GoapGoal.new()
			meat_acquisition_goal.name = "AcquireGroundMeatForTest"
			meat_acquisition_goal.goal_state = meat_goal
			route_agent.goals.clear()
			route_agent.goals.append(meat_acquisition_goal)
			route_agent.refresh_world_state()
			route_agent.resume()
			check(await until(func() -> bool:
				return (route_agent.current_plan != null and route_agent.current_action != null
					and route_agent.current_plan.actions[0].get_id().begins_with("PickUp:"))
			, 600), "an idle agent starts a pickup plan while distant meat is on the ground")
			route_agent.suspend()
			route_agent.goals.clear()
			route_agent.goals.append_array(saved_goals)
			meat_drop.position = Vector3(1, 0, 0)
	else:
		check(false, "meat acquisition test has an animal")
	route_agent.resume()
	check(await until(func() -> bool: return route_actor.drinks > 0, 1800),
		"nearby water collection completes through drinking")
	route_agent.suspend()
	var weapon_goal := GoapGoal.new()
	weapon_goal.name = "CraftWeaponForTest"
	weapon_goal.goal_state = GoapWorldState.new({Facts.HAS_WEAPON: true})
	route_agent.goals.clear()
	route_agent.goals.append(weapon_goal)
	check(not route_agent.actions.any(func(item: GoapAction) -> bool: return item.get_id().begins_with("Collect:")),
		"harvest and pickup remain separate actions")
	route_actor.deposit_item()
	route_actor.weapon_durability = 0
	var tree: Node3D
	var stone_source: Node3D
	for resource in route_world.resources:
		if resource.kind == &"tree":
			tree = resource
		elif resource.kind == &"stone":
			stone_source = resource
	if tree != null and stone_source != null:
		tree.position = route_actor.position + Vector3(2, 0, 0)
		stone_source.position = route_actor.position + Vector3(12, 0, 0)
		route_agent.refresh_world_state()
		route_agent.resume()
		var first_weapon_plan: bool = await until(func() -> bool: return route_agent.current_plan != null, 600)
		var first_weapon_action := route_agent.current_plan.actions[0].get_id() if first_weapon_plan else ""
		check(first_weapon_action.begins_with("Harvest:"),
			"weapon plan begins with a resource harvest")
		route_agent.suspend()
		tree.position = route_actor.position + Vector3(12, 0, 0)
		stone_source.position = route_actor.position + Vector3(2, 0, 0)
		route_agent.refresh_world_state()
		route_agent.resume()
		check(await until(func() -> bool: return route_agent.current_plan != null, 600)
			and route_agent.current_plan.actions[0].get_id() == first_weapon_action,
			"resource positions do not change an equal-cost action order")
		check(await until(func() -> bool: return route_actor.weapons_crafted > 0, 3600),
			"separate harvest, pickup and delivery actions supply workbench crafting")
	else:
		check(false, "weapon-order test has tree and stone sources")
	route_agent.suspend()
	route_world.set_agent_count(2)
	var rival: Node3D = route_world.actors[1]
	var rival_agent: GoapAgent = rival.get_node("GoapAgent")
	rival_agent.suspend()
	var camp: Node3D = route_world.get_node("Campfire")
	route_actor.position = camp.position + Vector3(0.5, 0, 0)
	rival.position = camp.position + Vector3(2, 0, 0)
	route_world.fire_remaining = 0
	route_actor.deposit_item()
	rival.deposit_item()
	for carrier in [route_actor, rival]:
		carrier.satiety = 100.0
		carrier.hydration = 100.0
		carrier.hungry = false
		carrier.thirsty = false
		route_world.drop_item(preload("res://goap_example/resources/wood.tres"), carrier.global_position)
		carrier.take_item_model(route_world.resources.back())
		carrier.get_node("GoapAgent").resume()
		carrier.get_node("GoapAgent").set_physics_process(false)
	await physics_frame
	await physics_frame
	route_agent.refresh_world_state()
	rival_agent.refresh_world_state()
	var lighting_action: GoapAction
	for action in route_agent.actions:
		if action.name == &"LightFire":
			lighting_action = action
			break
	if lighting_action != null:
		var fire_actions: Array[GoapAction] = [lighting_action]
		var fire_planner := GoapPlanner.new(fire_actions)
		var fire_goal := GoapWorldState.new({ Facts.HAS_FIRE: true })
		check(fire_planner.find_plan(route_agent.world_state, fire_goal) != null
			and fire_planner.find_plan(rival_agent.world_state, fire_goal) == null,
			"only the nominated Agent plans to light the campfire")
	else:
		check(false, "the lighting action exists")
	var first_lighting = route_actor.light_fire()
	var second_lighting = rival.light_fire()
	check(first_lighting.state == Execution.State.RUNNING
		and second_lighting.state == Execution.State.FAILED,
		"only one Agent can start lighting with the camp claim")
	check(await until(func() -> bool:
		return (first_lighting.state != Execution.State.RUNNING
			and second_lighting.state != Execution.State.RUNNING)
	, 180), "both lighting attempts finish")
	check(first_lighting.state == Execution.State.SUCCEEDED
		and second_lighting.state == Execution.State.FAILED
		and not route_actor.wood and rival.wood and route_world.fire_remaining > 0,
		"the first completed lighting consumes one Agent's wood")
	route_agent.suspend()
	rival_agent.suspend()
	rival.consume_item(&"wood")
	var shared_item = preload("res://goap_example/resources/item_definition.gd").new()
	shared_item.kind = &"shared_item_test"
	shared_item.inventory_key = &"shared_item_test"
	shared_item.title = "Shared item"
	route_world.drop_item(shared_item, Vector3(0, 0, 20), 1)
	var shared_target: Node3D
	for resource in route_world.resources:
		if resource.item == shared_item:
			shared_target = resource
			break
	if shared_target != null:
		route_actor.position = shared_target.position + Vector3(1, 0, 0)
		rival.position = shared_target.position - Vector3(1, 0, 0)
		rival_agent.refresh_world_state()
		route_agent.refresh_world_state()
		check(route_agent.world_state.get_state(shared_item.available_fact())
			and rival_agent.world_state.get_state(shared_item.available_fact()),
			"both Agents observe the same available item")
		var first_pickup = route_actor.pick_up(shared_item, shared_target)
		var second_pickup = rival.pick_up(shared_item, shared_target)
		check(first_pickup.state == Execution.State.RUNNING
			and second_pickup.state == Execution.State.RUNNING,
			"both Agents can target the same item")
		check(await until(func() -> bool:
			return (first_pickup.state != Execution.State.RUNNING
				and second_pickup.state != Execution.State.RUNNING)
		, 120), "both pickup attempts finish")
		check(first_pickup.state == Execution.State.SUCCEEDED
			and second_pickup.state == Execution.State.FAILED
			and route_actor.has_item(&"shared_item_test")
			and not rival.has_item(&"shared_item_test"),
			"only the first completed pickup receives the item")
	else:
		check(false, "shared pickup test created a ground item")
	route_world.queue_free()
	await process_frame
	print("GOAP example smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
