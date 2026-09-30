extends GoapGoal


func _init() -> void:
	name = &"Done"
	goal_state.set_state(&"done", true)
