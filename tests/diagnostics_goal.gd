extends GoapGoal

var priority := 20.0


func _init(id := "Finish", initial_priority := 20.0, fact: StringName = &"done") -> void:
	name = id
	priority = initial_priority
	goal_state = GoapWorldState.new({ fact: true })


func get_priority(_state: GoapWorldState) -> float:
	return priority
