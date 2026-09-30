extends RefCounted
## An actor-owned operation. No planner, GOAP facts or action names are involved.

enum State {
	RUNNING,
	SUCCEEDED,
	FAILED,
	CANCELLED,
}

var state := State.RUNNING
var actor: Node3D
var target: Node3D
var elapsed := 0.0
var reset_progress_on_movement := true
var label: String
var _needs_target := false
var _work: Callable
var _check: Callable
var resource_kind: StringName
var auto_select := false
var target_filter: Callable
var _selection_clock := 0.0
var _worked := false
var cleanup: Callable
var on_start: Callable


func _init(owner: Node3D, activity: String, work: Callable, check: Callable) -> void:
	actor = owner
	label = activity
	_work = work
	_check = check


func set_target(value: Node3D) -> void:
	target = value
	_needs_target = true


func start() -> void:
	if state != State.RUNNING:
		return
	if on_start.is_valid() and not on_start.call(self):
		_finish(State.FAILED)
		return
	if not resource_kind.is_empty() and not _prepare_resource(0.0):
		_finish(State.FAILED)


func advance(delta: float) -> void:
	if state != State.RUNNING:
		return
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		_finish(State.FAILED)
		return
	if not resource_kind.is_empty() and not _prepare_resource(delta):
		_finish(State.FAILED)
		return
	if _needs_target and (not is_instance_valid(target) or target.is_queued_for_deletion()):
		_finish(State.FAILED)
		return
	var readiness: State = _check.call(self)
	if readiness != State.RUNNING:
		_finish(readiness)
		return
	if _needs_target and not actor.approach(target.global_position, float(target.get_meta(&"interaction_radius", 1.6))):
		if reset_progress_on_movement:
			elapsed = 0.0
		return
	actor.stop_moving()
	_worked = true
	elapsed += delta
	var result: State = _work.call(self)
	if result != State.RUNNING:
		_finish(result)


func cancel() -> void:
	if state == State.RUNNING:
		_finish(State.CANCELLED)


func _prepare_resource(delta: float) -> bool:
	_selection_clock -= delta
	var valid: bool = is_instance_valid(target) and not target.is_queued_for_deletion() and target.available and (
		not target_filter.is_valid() or target_filter.call(target)
	)
	# Reconsider travel periodically, but finish work already in progress.
	if auto_select and (not valid or not _worked and _selection_clock <= 0):
		_selection_clock = 0.4
		var candidate: Node3D = actor.find_matching_resource(resource_kind, target_filter) if target_filter.is_valid() else actor.find_resource(resource_kind)
		if candidate != null and candidate != target:
			target = candidate
			elapsed = 0.0
			_worked = false
			valid = true
	return valid


func _finish(result: State) -> void:
	state = result
	if cleanup.is_valid():
		var release := cleanup
		cleanup = Callable()
		release.call(self)
	if is_instance_valid(actor):
		actor.stop_moving()
	target = null
	_work = Callable()
	_check = Callable()
	on_start = Callable()
	target_filter = Callable()
