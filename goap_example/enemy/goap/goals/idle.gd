extends GoapGoal


func _get_name() -> String:
	return "Idle"


func is_valid(_state: GoapWorldState) -> bool:
	return true


func get_priority() -> int:
	return 0
