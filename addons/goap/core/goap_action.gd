class_name GoapAction
extends RefCounted

enum Status {
	RUNNING,
	SUCCESS,
	FAILURE,
}

var name: StringName = _get_name()
var preconditions: GoapWorldState = _get_preconditions()
var effects: GoapWorldState = _get_effects()
## Default planning cost; game-specific adapters may provide another calculation.
var cost: float = _get_cost()


## Stable and unique within an agent. Override for parameterized actions.
func get_id() -> String:
	return String(name)


func is_relevant_to(requirements: GoapWorldState) -> bool:
	for key in effects.keys():
		if requirements.has_state(key) and effects.get_state(key) == requirements.get_state(key):
			return true
	return false


func is_consistent_with(requirements: GoapWorldState) -> bool:
	return not effects.conflicts(requirements)


## Runtime availability check; never called by the search worker.
func is_valid(_agent: GoapAgent) -> bool:
	return true


func start(_agent: GoapAgent) -> void:
	pass


func perform(_agent: GoapAgent, _delta: float) -> Status:
	return Status.SUCCESS


## Called once after each start, including success and interruption.
func stop(_agent: GoapAgent) -> void:
	pass


func _get_name() -> StringName:
	return &"UNNAMED"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new()


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new()


func _get_cost() -> float:
	return 1.0


func _to_string() -> String:
	return name
