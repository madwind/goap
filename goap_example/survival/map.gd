extends RefCounted
## Updated from the fixed camera's visible floor; all play stays on one screen.
static var half_size := Vector2(41.0, 29.0)
const CAMP_FENCE_RADIUS := 8.0
const CAMP_GATE_HALF_WIDTH := 2.0


static func camp_waypoint(from: Vector3, target: Vector3, camp: Vector3, steering: Dictionary) -> Vector3:
	var start := from - camp
	var finish := target - camp
	var start_inside := _inside_fence(start)
	var target_inside := _inside_fence(finish)
	var crosses := start_inside != target_inside or (not start_inside and _segment_crosses_fence(start, finish))
	if not crosses:
		steering.erase("route_gate")
		steering.erase("route_mode")
		steering.erase("route_phase")
		return target
	var mode := "exit" if start_inside else "enter"
	if steering.get("route_mode", "") != mode or not steering.has("route_gate"):
		var gates := [
			Vector3(-CAMP_FENCE_RADIUS - 1.1, 0, 0),
			Vector3(CAMP_FENCE_RADIUS + 1.1, 0, 0),
			Vector3(0, 0, -CAMP_FENCE_RADIUS - 1.1),
			Vector3(0, 0, CAMP_FENCE_RADIUS + 1.1),
		]
		var best := INF
		var choice := 0
		for index in gates.size():
			var point: Vector3 = gates[index]
			var score: float = (finish if start_inside else start).distance_squared_to(point)
			if score < best:
				best = score
				choice = index
		steering.route_gate = choice
		steering.route_mode = mode
		steering.route_phase = 0
	var gate := int(steering.route_gate)
	var inner := Vector3.ZERO
	var outer := Vector3.ZERO
	match gate:
		0:
			inner.x = -CAMP_FENCE_RADIUS + 1.1
			outer.x = -CAMP_FENCE_RADIUS - 1.1
		1:
			inner.x = CAMP_FENCE_RADIUS - 1.1
			outer.x = CAMP_FENCE_RADIUS + 1.1
		2:
			inner.z = -CAMP_FENCE_RADIUS + 1.1
			outer.z = -CAMP_FENCE_RADIUS - 1.1
		3:
			inner.z = CAMP_FENCE_RADIUS - 1.1
			outer.z = CAMP_FENCE_RADIUS + 1.1
	var first: Vector3 = inner if start_inside else outer
	if start.distance_to(first) < 0.85:
		steering.route_phase = 1
	if not start_inside and int(steering.route_phase) == 0 and _segment_nears_camp(start, outer, CAMP_FENCE_RADIUS + 0.55):
		# Follow the outside of the round fence until the gate is in clear view.
		var angle := atan2(start.z, start.x)
		var turn := wrapf(atan2(outer.z, outer.x) - angle, -PI, PI)
		angle += clampf(turn, -0.22, 0.22)
		return camp + Vector3(cos(angle), 0, sin(angle)) * (CAMP_FENCE_RADIUS + 1.1)
	return camp + (outer if start_inside else inner) if int(steering.route_phase) == 1 else camp + first


static func _inside_fence(point: Vector3) -> bool:
	return Vector2(point.x, point.z).length_squared() < CAMP_FENCE_RADIUS * CAMP_FENCE_RADIUS


static func _segment_crosses_fence(start: Vector3, finish: Vector3) -> bool:
	return _segment_nears_camp(start, finish, CAMP_FENCE_RADIUS)


static func _segment_nears_camp(start: Vector3, finish: Vector3, radius: float) -> bool:
	var origin := Vector2(start.x, start.z)
	var delta := Vector2(finish.x - start.x, finish.z - start.z)
	var along := clampf(-origin.dot(delta) / delta.length_squared(), 0.0, 1.0) if not delta.is_zero_approx() else 0.0
	return (origin + delta * along).length_squared() < radius * radius


static func move_on_ground(body: CharacterBody3D, direction: Vector3, speed: float, steering: Dictionary) -> void:
	direction.y = 0.0
	direction = direction.normalized()
	var delta := body.get_physics_process_delta_time()
	var remaining: float = maxf(0.0, steering.get("remaining", 0.0) - delta)
	steering.remaining = remaining
	var start := body.position
	body.velocity = (steering.direction if remaining > 0.0 else direction) * speed
	body.move_and_slide()
	# Collision recovery on capsules must not gradually lift characters away
	# from ground items. Sidestep trunks that block the direct campward route.
	body.position.y = 0.0
	var progress := Vector2(body.position.x - start.x, body.position.z - start.z).length()
	if remaining <= 0.0 and body.get_slide_collision_count() > 0 and progress < speed * delta * 0.25:
		# Commit to a short detour: a single sideways frame would alternate with
		# the direct route and get stuck against intersecting camp colliders.
		steering.direction = Vector3(-direction.z, 0.0, direction.x)
		steering.remaining = 0.65


static func clamp_position(value: Vector3) -> Vector3:
	return Vector3(
		clampf(value.x, -half_size.x, half_size.x),
		value.y,
		clampf(value.z, -half_size.y, half_size.y)
	)
