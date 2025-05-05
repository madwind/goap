class_name GoapAction

var name := _get_name()
var preconditions := _get_preconditions()
var effects := _get_effects()


func _get_name() -> StringName:
	return "UNNAMED"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new()


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new()


@warning_ignore("unused_parameter")
func is_valid(agent: GoapAgent) -> bool:
	return true


@warning_ignore("unused_parameter")
func get_cost(agent: GoapAgent, state: GoapWorldState) -> float:
	return 0.0


func perform(_agent: GoapAgent, _delta: float) -> bool:
	return false


func _to_string() -> String:
	return name
