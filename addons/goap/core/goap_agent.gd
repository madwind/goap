class_name GoapAgent
extends Node

signal plan_updated

@export_dir var goap_script_folder: String
@export var navigation_agent: NavigationAgent3D

var goals: Array[GoapGoal]
var actions: Array[GoapAction]
var world_state: GoapWorldState
var blackboard: Dictionary[StringName, Variant]
var current_action: GoapAction
var _planner: GoapPlanner
var _current_plan: GoapPlan
var debug := false
var actor: GoapActor:
	get:
		return get_parent()
var planning_start := 0


func _init_world_state() -> GoapWorldState:
	push_error("must be overridden")
	return


func _enter_tree() -> void:
	init_goap()


func _physics_process(delta: float) -> void:
	_follow_plan(delta)


func _follow_plan(delta: float) -> void:
	if _current_plan:
		_current_plan.execute(self, delta)


func _on_target_detected(body: Node3D) -> void:
	pass


func _on_target_lost(body: Node3D) -> void:
	pass


func _on_world_state_changed() -> void:
	planning_start = Time.get_ticks_msec()
	WorkerThreadPool.add_task(func():
		choose_best_plan.call_deferred(_planner.generate_candidate_plan_nodes())
	)


func init_goap(script_folder := goap_script_folder) -> void:
	world_state = _init_world_state()
	if not debug:
		world_state.state_changed.connect(_on_world_state_changed)
	load_goap_actions(script_folder)
	load_goap_goals(script_folder)
	connect_target_detection()
	_planner = GoapPlanner.new(self)


func load_goap_actions(script_folder: String) -> void:
	var actions_dir := script_folder.path_join("actions")
	var action_list := ResourceLoader.list_directory(actions_dir)
	for action_str in action_list:
		var action := ResourceLoader.load(actions_dir.path_join(action_str)).new() as GoapAction
		if action:
			actions.append(action)


func load_goap_goals(script_folder: String) -> void:
	var goals_dir := script_folder.path_join("goals")
	var goal_list := ResourceLoader.list_directory(goals_dir)
	for goal_str in goal_list:
		var goal := ResourceLoader.load(goals_dir.path_join(goal_str)).new() as GoapGoal
		if goal:
			goals.append(goal)


func connect_target_detection() -> void:
	for perception in get_children():
		if perception is GoapPerception:
			perception.target_detected.connect(_on_target_detected)
			perception.target_lost.connect(_on_target_lost)


func distance_to_target(target: Node3D) -> float:
	var paths := NavigationServer3D.map_get_path(
		navigation_agent.get_navigation_map(),
		actor.global_position,
		target.global_position,
		true)
	var distance := 0.0
	if paths.size() > 1:
			for i in range(paths.size() - 1):
				distance += paths[i].distance_to(paths[i + 1])
	return distance


func choose_best_plan(plan_nodes: Array[GoapPlanNode]):
	var best_plan: GoapPlan
	for plan_node in plan_nodes:
		var plan = GoapPlan.new(plan_node, self)
		if not best_plan or plan.cost < best_plan.cost:
			best_plan = plan
	_current_plan = best_plan
	_current_plan.planning_time_ms = Time.get_ticks_msec() - planning_start
	plan_updated.emit()
