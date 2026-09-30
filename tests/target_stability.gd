extends SceneTree

const Facts = preload("res://goap_example/survival/fact_keys.gd")
const Meat = preload("res://goap_example/resources/raw_meat.tres")

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TARGET STABILITY: " + message)


func until(predicate: Callable, frames := 600) -> bool:
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
	var actor: Node3D = world.actors[0]
	var agent: GoapAgent = actor.get_node("GoapAgent")
	agent.suspend()
	agent.asynchronous_planning = false
	actor.position = Vector3.ZERO
	actor.satiety = 11.0
	actor.hungry = true
	actor.hydration = 100.0
	actor.thirsty = false
	agent.goals = [preload("res://goap_example/agent/goap/goals/feed.gd").new()]
	for resource in world.resources:
		if resource.kind == &"animal":
			resource.position = Vector3(12, 0, 0)
			resource.home = resource.position
	agent.resume()
	var hunting := await until(func() -> bool:
		return agent.current_action != null and agent.current_action.get_id().begins_with("Harvest:animal/")
	)
	check(hunting, "hungry agent starts hunting")
	if hunting:
		var execution = agent.current_action.get("execution")
		var target: Node3D = execution.target
		check(target != null, "hunting holds a target")
		if target != null:
			var target_distance: float = actor.global_position.distance_to(target.global_position)
			world.drop_item(Meat, actor.global_position + Vector3.RIGHT * (target_distance + 2.0), 1)
			var generation := agent.planning_generation
			var plan := agent.current_plan
			agent.refresh_world_state()
			check(agent.world_state.get_state(Meat.available_fact()), "far meat is observed")
			check(agent.planning_generation == generation and agent.current_plan == plan,
				"farther drop keeps the current hunt and does not request replanning")
			actor.satiety = 11.0
			actor.hungry = true
			var before := agent.planning_generation
			actor.satiety = 13.0
			agent.refresh_world_state()
			check(agent.planning_generation > before,
				"a goal priority change requests replanning despite a far drop")
	world.queue_free()
	await process_frame
	print("GOAP target stability: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
