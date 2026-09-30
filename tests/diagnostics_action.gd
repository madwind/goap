extends GoapAction

var starts := 0
var stops := 0
var fail := false
var preempt := false


func _init(id := "Complete", action_cost := 2.5) -> void:
	name = StringName(id)
	cost = action_cost
	preconditions = GoapWorldState.new({ &"ready": true })
	effects = GoapWorldState.new({ &"done": true })


func get_cost_model() -> GDScript:
	return preload("res://tests/diagnostics_cost.gd")


func capture_context(_agent: GoapAgent) -> Dictionary:
	return { &"cost": cost }


func start(agent: GoapAgent) -> void:
	starts += 1
	if preempt:
		agent.suspend()


func perform(_agent: GoapAgent, _delta: float) -> Status:
	return Status.FAILURE if fail else Status.SUCCESS


func stop(_agent: GoapAgent) -> void:
	stops += 1
