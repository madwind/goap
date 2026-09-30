extends RefCounted
## Resource acquisition uses the target's data for both validation and drops.

const Execution = preload("res://goap_example/agent/abilities/execution.gd")
const Balance = preload("res://goap_example/survival/balance.gd")


static func harvest(actor: Node3D, target: Node3D, kind: StringName, profile: String, automatic := false, candidate_filter := Callable()) -> Execution:
	var execution := Execution.new(actor, "Harvest " + String(kind), _harvest, _resource_available)
	execution.resource_kind = kind
	execution.auto_select = automatic
	execution.target_filter = func(candidate: Node3D) -> bool:
		return candidate.can_harvest(actor) and candidate.harvest_profile() == profile and (
			not candidate_filter.is_valid() or candidate_filter.call(candidate)
		)
	# Preserve pending work while following a moving target; range is checked every tick.
	execution.reset_progress_on_movement = false
	execution.set_target(target)
	return execution


static func pick_up(actor: Node3D, item: Resource, target: Node3D, automatic := false, candidate_filter := Callable()) -> Execution:
	var signature: String = item.signature()
	var execution := Execution.new(actor, "Pick up " + item.title, _pick_up, _can_pick_up)
	execution.resource_kind = item.kind
	execution.auto_select = automatic
	execution.target_filter = func(candidate: Node3D) -> bool:
		return actor.can_carry_item() and candidate.item != null and candidate.item.signature() == signature and (
			not candidate_filter.is_valid() or candidate_filter.call(candidate)
		)
	execution.set_target(target)
	return execution


static func _resource_available(execution: Execution) -> Execution.State:
	return Execution.State.RUNNING if execution.target.available else Execution.State.FAILED


static func _can_pick_up(execution: Execution) -> Execution.State:
	return Execution.State.RUNNING if execution.target.available and execution.actor.can_carry_item() else Execution.State.FAILED


static func _harvest(execution: Execution) -> Execution.State:
	if execution.elapsed >= Balance.HARVEST_HIT_SECONDS:
		execution.elapsed = 0.0
		var damage: int = execution.actor.use_weapon_hunt_hit() if execution.target.harvest_method == &"hunt" else 1
		if execution.target.harvest_hit(damage):
			execution.actor.get_parent().record_event("Harvest completed; resource dropped its configured items")
			return Execution.State.SUCCEEDED
	return Execution.State.RUNNING


static func _pick_up(execution: Execution) -> Execution.State:
	if execution.elapsed < 0.3:
		return Execution.State.RUNNING
	if not execution.target.available:
		return Execution.State.FAILED
	var item: Resource = execution.target.item
	if not execution.actor.take_item_model(execution.target):
		return Execution.State.FAILED
	execution.actor.get_parent().record_event("Picked up " + item.title)
	return Execution.State.SUCCEEDED
