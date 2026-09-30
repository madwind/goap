extends RefCounted

const Execution = preload("res://goap_example/agent/abilities/execution.gd")


static func stow(actor: Node3D, camp: Node3D) -> Execution:
	var execution := Execution.new(actor, "Stow supplies", _deposit, _has_goods)
	execution.set_target(camp)
	return execution


static func _has_goods(execution: Execution) -> Execution.State:
	return Execution.State.RUNNING if not execution.actor.dead and execution.actor.has_held_goods() else Execution.State.FAILED


static func _deposit(execution: Execution) -> Execution.State:
	if execution.elapsed < 0.3:
		return Execution.State.RUNNING
	execution.actor.deposit_item()
	return Execution.State.SUCCEEDED
