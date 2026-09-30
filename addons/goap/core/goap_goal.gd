class_name GoapGoal
extends RefCounted

var name: String = _get_name()
var goal_state: GoapWorldState = _get_goal_state()


func get_id() -> String:
	return name


func is_valid(_state: GoapWorldState) -> bool:
	return true


func get_priority(_state: GoapWorldState) -> float:
	return 1.0


func _get_name() -> String:
	return "UNNAMED"


func _get_goal_state() -> GoapWorldState:
	return GoapWorldState.new()


func _to_string() -> String:
	return name
