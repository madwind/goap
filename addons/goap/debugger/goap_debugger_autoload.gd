extends Node

var goap_debugger: Control
var window: Window
var monitor: GoapRuntimeMonitor
var auto_show_monitor := true
var host: Control
var agents: Array[GoapAgent] = []
var observed: GoapAgent
var _registry_dirty := true
var _next_send_msec := 0
var _capture_registered := false
var performance_samples: GoapPerformanceStatistics
const AgentMarker = preload("goap_agent_marker.gd")
var _agent_numbers: Dictionary = {}
var _next_agent_number := 1
var marker_enabled := false
var all_markers_enabled := false
var agent_marker: CanvasLayer
var agent_markers: Dictionary = {}
var _markers_refresh_queued := false
var _sent_decision_generation := -1
var _paused_by_remote := false


func agent_descriptor(agent: GoapAgent) -> Dictionary:
	var id := agent.get_instance_id()
	var actor := AgentMarker.spatial_owner(agent)
	var owner_name := str(actor.name) if actor != null else str(agent.get_parent().name) if agent.get_parent() != null else str(agent.name)
	return {
		"id": id,
		"path": str(agent.get_path()) if agent.is_inside_tree() else str(agent.name),
		"label": "#%d · %s / %s" % [_agent_numbers.get(id, 0), owner_name, agent.name],
		"can_mark": actor != null,
	}


func _enter_tree() -> void:
	# Sample after the shared scheduler; collection never requires a game HUD.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	if DisplayServer.get_name() != "headless":
		# Let the scene provide a tab host before opening a standalone inspector.
		_show_unhosted.call_deferred()
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	if EngineDebugger.is_active():
		performance_samples = GoapPerformanceStatistics.new()
		EngineDebugger.register_message_capture("goap", _capture_command)
		_capture_registered = true
	_scan_existing.call_deferred()


func attach_to(container: Control) -> void:
	host = container
	_ensure_debugger()
	if goap_debugger.get_parent() != null:
		goap_debugger.reparent(host, false)
	else:
		host.add_child(goap_debugger)
	if is_instance_valid(monitor) and monitor.is_node_ready() and container != monitor.inspector_page:
		monitor.hide_monitor()
		monitor.queue_free()
		monitor = null
		window = null


func release_from(container: Control) -> void:
	if host == container:
		# The old scene owns and frees this view. The next scene gets a fresh view.
		host = null
		goap_debugger = null
		if DisplayServer.get_name() != "headless" and not is_queued_for_deletion():
			_show_unhosted.call_deferred()


func show_window() -> void:
	if is_instance_valid(host) and (
		not is_instance_valid(monitor) or host != monitor.inspector_page
	):
		return
	if not is_instance_valid(monitor):
		monitor = preload("../runtime/goap_runtime_monitor.tscn").instantiate()
		monitor.show_on_ready = false
		add_child(monitor)
		window = monitor.window
	elif not is_instance_valid(host):
		attach_to(monitor.inspector_page)
	monitor.show_monitor()


func _on_node_added(agent: Node) -> void:
	if agent is GoapAgent and not agents.has(agent):
		agents.append(agent)
		_agent_numbers[agent.get_instance_id()] = _next_agent_number
		_next_agent_number += 1
		_registry_dirty = true
		if goap_debugger != null:
			goap_debugger.add_agent(agent)
		agent.plan_updated.connect(_send_snapshot.bind(agent))
		if performance_samples != null:
			agent.planning_measured.connect(performance_samples.record_planning)
		if all_markers_enabled and not _markers_refresh_queued:
			_markers_refresh_queued = true
			_update_marker.call_deferred()


func _on_node_removed(agent: Node) -> void:
	if agent is GoapAgent:
		if agent == observed:
			agent.record_diagnostic("agent_removed", {})
			_send_events(agent)
			agent.end_diagnostics()
			observed = null
		_remove_marker(agent.get_instance_id())
		agents.erase(agent)
		_agent_numbers.erase(agent.get_instance_id())
		_registry_dirty = true
		if goap_debugger != null:
			goap_debugger.remove_agent(agent)
		if agent.plan_updated.is_connected(_send_snapshot.bind(agent)):
			agent.plan_updated.disconnect(_send_snapshot.bind(agent))
		if performance_samples != null and agent.planning_measured.is_connected(performance_samples.record_planning):
			agent.planning_measured.disconnect(performance_samples.record_planning)
		if all_markers_enabled and not _markers_refresh_queued:
			_markers_refresh_queued = true
			_update_marker.call_deferred()


func _send_snapshot(agent: GoapAgent) -> void:
	if not EngineDebugger.is_active() or agent != observed or agent.world_state == null:
		return
	var statistics: Dictionary = agent.planning_statistics.duplicate()
	var decisions: Dictionary = statistics.get("decisions", {})
	statistics.erase("decisions")
	var sequence: Array[String] = []
	if agent.current_plan != null:
		for action in agent.current_plan.actions:
			sequence.append(action.get_id())
	var payload := {
		"version": 2,
		"agent_id": agent.get_instance_id(),
		"agent": str(agent.get_path()),
		"label": agent_descriptor(agent).label,
		"generation": agent.planning_generation,
		"goal": agent.current_goal.name if agent.current_goal != null else "",
		"world": agent.world_state.to_dictionary(),
		"actions": sequence,
		"cost_labels": agent.get_plan_cost_labels(agent.current_plan) if agent.current_plan != null and agent.has_method("get_plan_cost_labels") else [],
		"step": agent.current_plan.step if agent.current_plan != null else -1,
		"started": agent.current_plan._started if agent.current_plan != null else false,
		"cost": agent.current_plan.cost if agent.current_plan != null else null,
		"search_complete": agent.current_plan.search_complete if agent.current_plan != null else null,
		"is_planning": agent.is_planning(),
		"statistics": statistics,
		"trace": agent.planning_trace.slice(0, 128) if agent.debug else []
	}
	var report_generation := int(statistics.get("generation", -1))
	if not decisions.is_empty() and report_generation != _sent_decision_generation:
		payload.decisions = decisions
		_sent_decision_generation = report_generation
	EngineDebugger.send_message("goap:plan", [payload])


func _process(_delta: float) -> void:
	if not EngineDebugger.is_active():
		return
	if _paused_by_remote and not get_tree().paused:
		_paused_by_remote = false
	var scheduler := get_tree().get_meta(&"goap_planning_scheduler", null) as GoapPlanningScheduler
	if is_instance_valid(scheduler) and not get_tree().paused:
		performance_samples.record_frame(scheduler.statistics)
	var now := Time.get_ticks_msec()
	if now < _next_send_msec:
		return
	_next_send_msec = now + 100
	EngineDebugger.send_message("goap:performance", [{ "version": 2, "metrics": performance_snapshot(), "paused": get_tree().paused }])
	if _registry_dirty:
		var registry: Array[Dictionary] = []
		for agent in agents:
			if is_instance_valid(agent) and agent.is_inside_tree():
				registry.append(agent_descriptor(agent))
		EngineDebugger.send_message("goap:agents", [{ "version": 2, "agents": registry }])
		_registry_dirty = false
	if is_instance_valid(observed):
		_send_events(observed)
		_send_snapshot(observed)


func performance_snapshot() -> Dictionary:
	if performance_samples == null:
		return {}
	var scheduler := get_tree().get_meta(&"goap_planning_scheduler", null) as GoapPlanningScheduler
	return performance_samples.snapshot(
		scheduler.statistics if is_instance_valid(scheduler) else {},
		scheduler.frame_budget_ms if is_instance_valid(scheduler) else float(ProjectSettings.get_setting("goap/planning/frame_budget_ms", 2.0)),
		agents.size()
	)


func _send_events(agent: GoapAgent) -> void:
	if not EngineDebugger.is_active():
		return
	var events := agent.take_diagnostic_events()
	if not events.is_empty():
		EngineDebugger.send_message("goap:events", [{ "version": 2, "agent_id": agent.get_instance_id(), "events": events, "dropped": agent.diagnostic_dropped }])


func _capture_command(message: String, data: Array) -> bool:
	if message == "set_paused":
		if data.size() != 1 or not data[0] is bool:
			return false
		get_tree().paused = data[0]
		_paused_by_remote = data[0]
		_next_send_msec = 0
		return true
	if message == "show_all_markers":
		if data.size() != 1 or not data[0] is bool:
			return false
		all_markers_enabled = data[0]
		_update_marker()
		return true
	if message == "show_marker":
		if data.size() != 1 or not data[0] is bool:
			return false
		marker_enabled = data[0]
		_update_marker()
		return true
	if message == "reset_performance":
		if not data.is_empty() or performance_samples == null:
			return false
		performance_samples.reset()
		_next_send_msec = 0
		return true
	if message == "list":
		_registry_dirty = true
		return true
	if message != "observe" or data.size() != 1 or not data[0] is int:
		return false
	if is_instance_valid(observed):
		observed.end_diagnostics()
	observed = null
	_sent_decision_generation = -1
	for agent in agents:
		if agent.get_instance_id() == int(data[0]):
			observed = agent
			agent.begin_diagnostics()
			_send_snapshot(agent)
			break
	_update_marker()
	return true


func _update_marker() -> void:
	_markers_refresh_queued = false
	var desired: Dictionary = {}
	var owner_slots: Dictionary = {}
	agent_marker = null
	var candidates: Array = agents if all_markers_enabled else [observed] if marker_enabled else []
	for agent: GoapAgent in candidates:
		if not is_instance_valid(agent) or not agent.is_inside_tree() or agent.is_queued_for_deletion():
			continue
		if not all_markers_enabled and not (marker_enabled and agent == observed):
			continue
		var actor := AgentMarker.spatial_owner(agent)
		if actor == null:
			continue
		var id := agent.get_instance_id()
		desired[id] = true
		var marker: CanvasLayer = agent_markers.get(id)
		if not is_instance_valid(marker):
			marker = AgentMarker.new()
			agent_markers[id] = marker
			add_child(marker)
		marker.highlighted = agent == observed
		marker.stack_index = int(owner_slots.get(actor.get_instance_id(), 0))
		owner_slots[actor.get_instance_id()] = marker.stack_index + 1
		marker.track(agent, agent_descriptor(agent).label)
		if agent == observed:
			agent_marker = marker
	for id in agent_markers.keys():
		if not desired.has(id):
			_remove_marker(id)


func _remove_marker(id: int) -> void:
	var marker: CanvasLayer = agent_markers.get(id)
	if is_instance_valid(marker):
		if agent_marker == marker:
			agent_marker = null
		marker.hide()
		# Detach while the actor's Viewport still exists during scene teardown.
		marker.custom_viewport = get_viewport()
		marker.queue_free()
	agent_markers.erase(id)


func _scan_existing() -> void:
	var pending: Array[Node] = [get_tree().root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		_on_node_added(node)
		pending.append_array(node.get_children())


func _exit_tree() -> void:
	if _paused_by_remote and get_tree().paused:
		get_tree().paused = false
	for id in agent_markers.keys():
		_remove_marker(id)
	if is_instance_valid(observed):
		observed.end_diagnostics()
	if _capture_registered:
		EngineDebugger.unregister_message_capture("goap")
	for agent in agents:
		if is_instance_valid(agent) and performance_samples != null and agent.planning_measured.is_connected(performance_samples.record_planning):
			agent.planning_measured.disconnect(performance_samples.record_planning)


func _ensure_debugger() -> void:
	if not is_instance_valid(goap_debugger):
		goap_debugger = preload("goap_debugger.tscn").instantiate()
		for agent in agents:
			goap_debugger.add_agent(agent)


func _show_unhosted() -> void:
	if is_inside_tree() and auto_show_monitor and not is_instance_valid(host):
		show_window()


func set_auto_show_monitor(enabled: bool) -> void:
	auto_show_monitor = enabled
	if not enabled and is_instance_valid(monitor):
		monitor.hide_monitor()
		monitor.queue_free()
		monitor = null
		window = null
		if is_instance_valid(host):
			host = null
			goap_debugger = null
	elif enabled and DisplayServer.get_name() != "headless":
		_show_unhosted.call_deferred()
