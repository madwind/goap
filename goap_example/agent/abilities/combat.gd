extends RefCounted

const Execution = preload("res://goap_example/agent/abilities/execution.gd")
const Balance = preload("res://goap_example/survival/balance.gd")
const Map = preload("res://goap_example/survival/map.gd")


static func attack(actor: Node3D, target: Node3D) -> Execution:
	var execution := Execution.new(actor, "Attack monster", _attack, _target_is_threat)
	execution.reset_progress_on_movement = false
	execution.set_target(target)
	return execution


static func _target_is_threat(execution: Execution) -> Execution.State:
	if execution.actor.dead or execution.actor.is_low_health() or execution.actor.is_starving() or execution.actor.is_dehydrated():
		return Execution.State.FAILED
	return Execution.State.RUNNING if is_instance_valid(execution.target) and execution.target.health > 0 and execution.actor.get_threat() == execution.target else Execution.State.SUCCEEDED


static func _attack(execution: Execution) -> Execution.State:
	if execution.elapsed >= Balance.HARVEST_HIT_SECONDS:
		execution.elapsed = 0.0
		execution.target.take_damage(execution.actor.use_weapon_hit())
	return Execution.State.RUNNING


static func flee_monster(actor: Node3D) -> Execution:
	return Execution.new(actor, "Flee monster", _flee, _needs_flee)


static func _needs_flee(execution: Execution) -> Execution.State:
	if execution.actor.dead:
		return Execution.State.FAILED
	return Execution.State.RUNNING if execution.actor.is_low_health() and execution.actor.is_in_danger() else Execution.State.SUCCEEDED


static func _flee(execution: Execution) -> Execution.State:
	var actor: Node3D = execution.actor
	var threat: Node3D = actor.get_parent().nearest_monster(actor.global_position, Balance.FLEE_CLEAR_RADIUS)
	if threat == null:
		return Execution.State.SUCCEEDED
	var away: Vector3 = actor.global_position - threat.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT
	away = away.normalized()
	var best_position: Vector3 = actor.global_position
	var best_gain := 0.25
	var best_score := 0.0
	var current_distance: float = actor.global_position.distance_to(threat.global_position)
	for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]:
		var candidate: Vector3 = Map.clamp_position(actor.global_position + away.rotated(Vector3.UP, angle) * Balance.FLEE_END_RADIUS)
		var travel_distance: float = actor.global_position.distance_to(candidate)
		if travel_distance < 0.5:
			continue
		var gain: float = candidate.distance_to(threat.global_position) - current_distance
		# Prefer immediate separation over a farther endpoint reached by cutting across the threat.
		var score: float = gain / travel_distance
		if gain > 0.25 and score > best_score:
			best_score = score
			best_gain = gain
			best_position = candidate
	if best_gain <= 0.25:
		var camp: Node3D = actor.get_camp()
		if camp == null:
			return Execution.State.FAILED
		best_position = camp.global_position
	actor.move_to(best_position, Balance.FLEE_SPEED_MULTIPLIER)
	return Execution.State.RUNNING


static func rest_at_camp(actor: Node3D, camp: Node3D) -> Execution:
	var execution := Execution.new(actor, "Rest at camp", _rest, _needs_rest)
	execution.set_target(camp)
	return execution


static func _needs_rest(execution: Execution) -> Execution.State:
	return Execution.State.FAILED if execution.actor.dead else Execution.State.RUNNING


static func _rest(execution: Execution) -> Execution.State:
	# Only eating meat restores health.
	return Execution.State.SUCCEEDED
