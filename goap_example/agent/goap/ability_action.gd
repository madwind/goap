extends GoapAction
## Planner adapter for execution status translation and cancellation.

const Execution = preload("res://goap_example/agent/abilities/execution.gd")
var execution: Execution


func perform(_agent: GoapAgent, _delta: float) -> Status:
	if execution == null:
		return Status.FAILURE
	match execution.state:
		Execution.State.RUNNING: return Status.RUNNING
		Execution.State.SUCCEEDED: return Status.SUCCESS
		_: return Status.FAILURE


func stop(_agent: GoapAgent) -> void:
	if execution != null:
		execution.cancel()
	execution = null
