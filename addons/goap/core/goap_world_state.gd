class_name GoapWorldState

var _state: Dictionary[StringName, bool] = {}
signal state_changed


func _init(state: Dictionary[StringName, bool] = {}) -> void:
	_state = state


func set_state(key: StringName, value: bool) -> void:
	if _state.get(key) != value:
		_state.set(key, value)
		state_changed.emit()


func get_state(key: StringName, default: Variant = null) -> Variant:
	return _state.get(key, default)


func contains(other_state: GoapWorldState) -> bool:
	for key: StringName in other_state.keys():
		if _state.get(key) != other_state.get(key):
			return false
	return true


func get_unsatisfied_goals(goal_state: GoapWorldState) -> GoapWorldState:
	var unsatisfied_state: Dictionary[StringName, bool] = {}
	for key in goal_state.keys():
		if get_state(key) != goal_state.get_state(key):
			unsatisfied_state.set(key, goal_state.get_state(key))
	return GoapWorldState.new(unsatisfied_state)


func merge(other_state: GoapWorldState, emit_change := false) -> void:
	var should_emit_change = false
	if emit_change:
		should_emit_change = not contains(other_state)
	_state.merge(other_state._state, true)
	if should_emit_change:
		state_changed.emit()


func duplicate() -> GoapWorldState:
	return GoapWorldState.new(_state.duplicate())


func match_first(other_state: GoapWorldState) -> bool:
	for key in other_state.keys():
		return get_state(key) == other_state.get_state(key)
	return false


func size() -> int:
	return _state.size()


func keys() -> Array[StringName]:
	return _state.keys()


func _to_string() -> String:
	return str(_state)
