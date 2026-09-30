extends GoapAction


func _init() -> void:
	name = &"Complete"
	effects.set_state(&"done", true)


func get_cost_model() -> GDScript:
	return preload("res://tests/export_fixture/costs/derived.gd")
