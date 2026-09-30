class_name GoapPlanningSnapshot
extends RefCounted
## Shared snapshot construction for synchronous and time-sliced preparation.
## Records and prepared dictionaries for planning snapshots.

## Main-thread cache of the last ordered, available action set. Published data
## is immutable, so old workers can continue using it while a new set is built.
var _cached: Dictionary = {}


static func capture_action(action: GoapAction, seen_ids: Dictionary) -> Dictionary:
	var id := action.get_id()
	if id.is_empty() or seen_ids.has(id):
		return {}
	seen_ids[id] = true
	var record := {
		"id": id,
		"preconditions": action.preconditions.snapshot(),
		"effects": action.effects.snapshot()
	}
	record.make_read_only()
	return record


static func empty_prepared() -> Dictionary:
	return { "records": [], "effect_index": {} }


static func append_record(prepared: Dictionary, record: Dictionary) -> void:
	var action_index: int = prepared.records.size()
	prepared.records.append(record)
	for key: StringName in record.effects:
		var fact := fact_key(key, record.effects[key])
		if not prepared.effect_index.has(fact):
			prepared.effect_index[fact] = []
		prepared.effect_index[fact].append(action_index)


static func prepare(records: Array) -> Dictionary:
	var prepared := empty_prepared()
	for record: Dictionary in records:
		append_record(prepared, record)
	return prepared


static func fact_key(key: StringName, value: bool) -> String:
	return "%d:%s=%d" % [key.length(), key, int(value)]


func reuse(records: Array) -> Dictionary:
	if _cached.is_empty() or records.size() != _cached.records.size():
		return {}
	for index in records.size():
		var previous: Dictionary = _cached.records[index]
		var current: Dictionary = records[index]
		if previous.id != current.id \
				or not is_same(previous.preconditions, current.preconditions) \
				or not is_same(previous.effects, current.effects):
			return {}
	return _cached


func remember(prepared: Dictionary) -> void:
	# capture_action() already sealed each record and its fact snapshots.
	# Only touch the newly built containers; old workers may share the facts.
	for indices: Array in prepared.effect_index.values():
		indices.make_read_only()
	prepared.effect_index.make_read_only()
	prepared.records.make_read_only()
	prepared.make_read_only()
	_cached = prepared


func get_or_prepare(records: Array) -> Dictionary:
	var prepared := reuse(records)
	if prepared.is_empty():
		prepared = prepare(records)
		remember(prepared)
	return prepared
