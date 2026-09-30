@tool
extends Resource
## Shared by resource drops, ground items and the planner adapter.

const Facts = preload("res://goap_example/survival/fact_keys.gd")

@export var kind: StringName
@export var inventory_key: StringName
@export var title: String
@export var color := Color.WHITE


func available_fact() -> StringName:
	return Facts.available(signature())


func inventory_fact() -> StringName:
	return inventory_fact_for(inventory_key)


static func inventory_fact_for(key: StringName) -> StringName:
	return Facts.inventory(key)


func signature() -> String:
	# Escape separators so authored names cannot collide with the profile syntax.
	var item_name := String(kind).uri_encode()
	if kind == inventory_key:
		return item_name
	return "%s=%s" % [item_name, String(inventory_key).uri_encode()]
