class_name GoapGoal

var name := _get_name()
var desired_state := _get_desired_state()


func _get_name() -> String:
	return "UNNAMEED"


func is_valid(current_state: GoapWorldState) -> bool:
	return true


func get_priority() -> int:
	return 0


func _get_desired_state() -> GoapWorldState:
	return GoapWorldState.new()


func _to_string() -> String:
	return name
