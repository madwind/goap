extends RefCounted
## Owns benchmark configuration and synthetic planners, independent of gameplay.

const StressAgent = preload("res://goap_example/stress_agent.gd")
var config: Dictionary = {}
var _monitor: VBoxContainer


func initialize(tree: SceneTree, monitor: VBoxContainer) -> void:
	_monitor = monitor
	config = tree.get_meta(&"example_stress_config", {}).duplicate()


func set_config(value: Dictionary, tree: SceneTree) -> void:
	config = value.duplicate()
	tree.set_meta(&"example_stress_config", config.duplicate())


func record_survival_planning(report: Dictionary) -> void:
	if config.is_empty():
		_monitor.record_planning(report)


func configure_population(actors: Array[Node3D]) -> void:
	_monitor.agent_count = actors.size()
	_monitor.stress_config = config.duplicate()
	_monitor.reset_samples()
	_monitor.stress_agents.clear()
	for actor in actors:
		_configure_actor(actor)


func restart_round(actors: Array[Node3D]) -> bool:
	if config.is_empty():
		return false
	_monitor.reset_samples()
	for actor in actors:
		actor.get_node("StressPlanner").restart_round()
	return true


func reset_samples(actors: Array[Node3D]) -> void:
	if not restart_round(actors):
		_monitor.reset_samples()


func _configure_actor(actor: Node3D) -> void:
	var previous := actor.get_node_or_null("StressPlanner")
	if previous != null:
		actor.remove_child(previous)
		previous.queue_free()
	if config.is_empty():
		return
	# Synthetic requests share the scheduler without controlling the actor.
	var planner := StressAgent.new()
	planner.goal_count = config.goals
	planner.steps_per_goal = config.steps
	planner.alternatives_per_step = config.alternatives
	planner.max_planning_nodes = config.limit
	planner.name = "StressPlanner"
	planner.planning_measured.connect(_monitor.record_planning)
	_monitor.stress_agents.append(planner)
	actor.add_child(planner)
