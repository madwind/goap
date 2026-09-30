class_name GoapWorldState
extends RefCounted
## Boolean planning data, independent of scene objects and observation providers.

signal state_changed
var _state: Dictionary[StringName, bool] = {}
var _snapshot: Dictionary[StringName, bool] = {}
var _snapshot_dirty := true


## Structural key: preserve explicit false constraints in partial definitions.
static func key_for(data: Dictionary[StringName, bool]) -> String:
	var ordered := data.keys()
	ordered.sort()
	var parts := PackedStringArray()
	for key in ordered:
		# Length prefix prevents collisions for names containing separators.
		parts.append("%d:%s=%d" % [key.length(), key, int(data[key])])
	return "|".join(parts)


func _init(state: Dictionary[StringName, bool] = {}) -> void:
	_state = state.duplicate()


func set_state(key: StringName, value: bool) -> void:
	if not _state.has(key) or _state[key] != value:
		var changed := get_state(key) != value
		_state[key] = value
		_snapshot_dirty = true
		if changed:
			state_changed.emit()


## Unprovided facts are false.
func get_state(key: StringName) -> bool:
	return _state.get(key, false)


## Whether a partial definition explicitly specifies this fact.
func has_state(key: StringName) -> bool:
	return _state.has(key)


func satisfies(other: GoapWorldState) -> bool:
	for key in other._state:
		if get_state(key) != other._state[key]:
			return false
	return true


func conflicts(other: GoapWorldState) -> bool:
	for key in other.keys():
		if _state.has(key) and _state[key] != other._state[key]:
			return true
	return false


## Requirements in this state not satisfied by other; missing facts are false.
func difference(other: GoapWorldState) -> GoapWorldState:
	var result := GoapWorldState.new()
	for key in keys():
		if _state[key] != other.get_state(key):
			result._state[key] = _state[key]
	return result


func merge(other: GoapWorldState, emit_change := true) -> void:
	var changed := not satisfies(other)
	for key in other._state:
		if not _state.has(key) or _state[key] != other._state[key]:
			_state[key] = other._state[key]
			_snapshot_dirty = true
	if changed and emit_change:
		state_changed.emit()


func duplicate() -> GoapWorldState:
	return GoapWorldState.new(_state)


## Publish a complete observation atomically. Facts no longer observed disappear
## (and therefore read as false). Existing immutable snapshots remain valid.
func replace(other: GoapWorldState) -> void:
	var data := other.to_dictionary()
	if _state == data:
		return
	var changed := not satisfies(other) or not other.satisfies(self)
	_state = data
	_snapshot_dirty = true
	if changed:
		state_changed.emit()


func to_dictionary() -> Dictionary[StringName, bool]:
	return _state.duplicate()


## Immutable planning view, rebuilt only after a fact changes. Old views remain valid.
func snapshot() -> Dictionary[StringName, bool]:
	if _snapshot_dirty:
		_snapshot = _state.duplicate()
		_snapshot.make_read_only()
		_snapshot_dirty = false
	return _snapshot


func get_key() -> String:
	return key_for(_state)


func size() -> int:
	return _state.size()


func keys() -> Array[StringName]:
	var result := _state.keys()
	result.sort()
	return result


func _to_string() -> String:
	return str(_state)
