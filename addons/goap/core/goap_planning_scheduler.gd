class_name GoapPlanningScheduler
extends Node
## One scheduler per SceneTree. Main-thread preparation/result budget applies
## to all agents together per rendered frame. Workers search AND evaluate costs.

var frame_budget_ms := 2.0
var slice_budget_ms := 0.25
var worker_slice_ms := 2.0
var max_worker_tasks := 2
var statistics: Dictionary = {}
var _queue: Array[WeakRef] = []
var _queued: Dictionary = {}
var _workers: Array[GoapPlanningRequest] = []


static func for_tree(tree: SceneTree) -> GoapPlanningScheduler:
	var existing: Variant = tree.get_meta(&"goap_planning_scheduler") if tree.has_meta(
		&"goap_planning_scheduler"
	) else null
	if is_instance_valid(existing):
		return existing
	var scheduler := GoapPlanningScheduler.new()
	scheduler.name = "GoapPlanningScheduler"
	scheduler.frame_budget_ms = float(
		ProjectSettings.get_setting("goap/planning/frame_budget_ms", 2.0)
	)
	scheduler.slice_budget_ms = float(
		ProjectSettings.get_setting("goap/planning/slice_budget_ms", 0.25)
	)
	scheduler.worker_slice_ms = float(
		ProjectSettings.get_setting("goap/planning/worker_slice_ms", 2.0)
	)
	scheduler.max_worker_tasks = int(
		ProjectSettings.get_setting("goap/planning/max_worker_tasks", 2)
	)
	tree.set_meta(&"goap_planning_scheduler", scheduler)
	tree.root.add_child.call_deferred(scheduler)
	return scheduler


func _process(_delta: float) -> void:
	process_budget()


func enqueue(agent: GoapAgent) -> void:
	if agent.is_suspended:
		return
	agent.attach_planning_scheduler(self)
	var id := agent.get_instance_id()
	if not _queued.has(id):
		_queued[id] = true
		_queue.append(weakref(agent))


func remove(agent: GoapAgent) -> void:
	_queued.erase(agent.get_instance_id())
	_queue = _queue.filter(func(item: WeakRef) -> bool: return item.get_ref() != agent)


func dispatch(request: GoapPlanningRequest) -> bool:
	if _workers.size() >= maxi(1, max_worker_tasks):
		return false
	request.task_id = WorkerThreadPool.add_task(
		GoapPlanningRequest.planning_slice.bind(
			request.worker_data,
			maxi(1, int(worker_slice_ms * 1000.0))
		)
	)
	_workers.append(request)
	return true


## Also callable on a detached scheduler by tests to simulate a frame.
func process_budget() -> void:
	var started := Time.get_ticks_usec()
	var deadline := started + maxi(0, int(frame_budget_ms * 1000.0))
	var peak_workers := _workers.size()
	for index in range(_workers.size() - 1, -1, -1):
		var request := _workers[index]
		if WorkerThreadPool.is_task_completed(request.task_id):
			WorkerThreadPool.wait_for_task_completion(request.task_id)
			request.task_id = -1
			_workers.remove_at(index)
	var idle_visits := 0
	var slices := 0
	var max_slice_usec := 0
	while not _queue.is_empty() and Time.get_ticks_usec() < deadline:
		var reference := _queue.pop_front()
		var agent: GoapAgent = reference.get_ref()
		if agent == null:
			continue
		_queued.erase(agent.get_instance_id())
		var slice_started := Time.get_ticks_usec()
		var slice_deadline := mini(deadline, slice_started + maxi(1, int(slice_budget_ms * 1000.0)))
		var progressed := agent.advance_planning(slice_deadline, self)
		max_slice_usec = maxi(max_slice_usec, Time.get_ticks_usec() - slice_started)
		peak_workers = maxi(peak_workers, _workers.size())
		slices += 1
		if agent.is_planning():
			enqueue(agent)
		idle_visits = 0 if progressed else idle_visits + 1
		if idle_visits >= _queue.size():
			break
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	statistics = {
		"frame_time_ms": elapsed,
		"budget_ms": frame_budget_ms,
		"overrun_ms": maxf(0.0, elapsed - frame_budget_ms),
		"max_slice_ms": max_slice_usec / 1000.0,
		"slices": slices,
		"queued_agents": _queue.size(),
		"active_workers": _workers.size(),
		"peak_workers": peak_workers
	}


func _exit_tree() -> void:
	# Jobs yield after a short planning slice; never abandon a running worker.
	for request in _workers:
		request.cancelled = true
		WorkerThreadPool.wait_for_task_completion(request.task_id)
		request.task_id = -1
	_workers.clear()
	_queue.clear()
	_queued.clear()
	if is_inside_tree() and get_tree().has_meta(&"goap_planning_scheduler") and get_tree().get_meta(
		&"goap_planning_scheduler"
	) == self:
		get_tree().remove_meta(&"goap_planning_scheduler")
