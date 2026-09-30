extends RefCounted

const Execution = preload("res://goap_example/agent/abilities/execution.gd")
const Balance = preload("res://goap_example/survival/balance.gd")


static func light_fire(actor: Node3D, camp: Node3D) -> Execution:
	var execution := Execution.new(actor, "Light fire", _light_fire, _can_light_fire)
	execution.set_target(camp)
	execution.on_start = camp.claim_fire
	execution.cleanup = camp.release_fire
	return execution


static func cook_meat(actor: Node3D, camp: Node3D) -> Execution:
	var execution := Execution.new(actor, "Cook meat", _cook_meat, _can_cook)
	execution.set_target(camp)
	return execution


static func _can_light_fire(execution: Execution) -> Execution.State:
	return Execution.State.RUNNING if execution.actor.wood and execution.actor.get_camp().can_tend_fire(execution.actor) else Execution.State.FAILED


static func _light_fire(execution: Execution) -> Execution.State:
	if execution.elapsed < 1.0:
		return Execution.State.RUNNING
	return Execution.State.SUCCEEDED if execution.actor.get_camp().finish_fire(execution) else Execution.State.FAILED


static func _can_cook(execution: Execution) -> Execution.State:
	return Execution.State.RUNNING if execution.actor.raw_meat and execution.actor.get_camp().has_fire() else Execution.State.FAILED


static func _cook_meat(execution: Execution) -> Execution.State:
	if execution.elapsed < 2.0:
		return Execution.State.RUNNING
	execution.actor.cook_carried_meat()
	execution.actor.get_parent().record_event("Finished cooking meat")
	return Execution.State.SUCCEEDED
