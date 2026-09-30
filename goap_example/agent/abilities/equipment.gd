extends RefCounted

const Execution = preload("res://goap_example/agent/abilities/execution.gd")


static func craft_weapon(actor: Node3D, workbench: Node3D) -> Execution:
	var execution := Execution.new(actor, "Craft stone axe", _craft, _has_materials)
	execution.set_target(workbench)
	return execution


static func _has_materials(execution: Execution) -> Execution.State:
	var actor := execution.actor
	return Execution.State.RUNNING if not actor.dead and actor.weapon_durability == 0 and actor.get_camp().has_crafting_materials() \
		and execution.target == actor.get_camp().workbench() else Execution.State.FAILED


static func _craft(execution: Execution) -> Execution.State:
	if execution.elapsed < 2.0:
		return Execution.State.RUNNING
	return Execution.State.SUCCEEDED if execution.actor.finish_weapon() else Execution.State.FAILED
