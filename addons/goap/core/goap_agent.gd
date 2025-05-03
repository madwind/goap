extends Node
class_name GoapAgent

@export_dir var goap_script_folder: String
@export var navigation_agent: NavigationAgent3D

var goals: Array[GoapGoal]
var actions: Array[GoapAction]
var world_state: GoapWorldState
var blackboard: Dictionary[StringName, Variant]
var current_action: GoapAction
var _planner: GoapPlanner
var _current_plan: GoapPlan
var _target_positions: Dictionary[Node3D, Vector3]
var debug := false
var actor: GoapActor:
	get:
		return get_parent()


func _enter_tree() -> void:
	init_goap()


func init_goap(script_folder := goap_script_folder) -> void:
	world_state = GoapWorldState.new()
	if not debug:
		world_state.state_changed.connect(_world_state_changed)
	_init_world_state()
	var actions_dir := script_folder.path_join("actions")
	var action_list := ResourceLoader.list_directory(actions_dir)
	for action_str in action_list:
		var action := ResourceLoader.load(actions_dir.path_join(action_str)).new() as GoapAction
		if action:
			actions.append(action)

	var goals_dir := script_folder.path_join("goals")
	var goal_list := ResourceLoader.list_directory(goals_dir)
	for goal_str in goal_list:
		var goal := ResourceLoader.load(goals_dir.path_join(goal_str)).new() as GoapGoal
		if goal:
			goals.append(goal)

	for target in get_children():
		if target is GoapPerception:
			target.target_detected.connect(record_target)
	_planner = GoapPlanner.new(self)


func _init_world_state() -> void:
	pass


func record_target(body: Node3D) -> void:
	if _target_positions.get(body) != body.global_position:
		_target_positions.set(body, body.global_position)
		_on_target_changed(body)


func _physics_process(delta: float) -> void:
	_follow_plan(delta)


func _follow_plan(delta: float) -> void:
	if _current_plan:
		_current_plan.execute(self, delta)
	#if _current_plan.actions.size() == 0:
		#return


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


func _on_target_changed(body: Node3D) -> void:
	pass


func _world_state_changed() -> void:
	_current_plan = _planner.get_best_plan()
