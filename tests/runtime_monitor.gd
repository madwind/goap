extends SceneTree
## This fixture also runs in an isolated project containing only addons/goap.

var checks := 0
var failures := 0


class WaitingAction extends GoapAction:
	func perform(_agent: GoapAgent, _delta: float) -> Status:
		return Status.RUNNING


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RUNTIME MONITOR: " + message)


func make_agent() -> GoapAgent:
	var agent := GoapAgent.new()
	agent.asynchronous_planning = false
	var action := WaitingAction.new()
	action.name = "Complete"
	action.effects.set_state(&"done", true)
	var goal := GoapGoal.new()
	goal.name = "Finish"
	goal.goal_state.set_state(&"done", true)
	agent.actions.assign([action])
	agent.goals.assign([goal])
	return agent


func finish_request(agent: GoapAgent) -> void:
	for frame in 300:
		await process_frame
		if not agent.is_planning():
			return
	check(false, "request completes within 300 frames")


func run() -> void:
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var first := make_agent()
	scene.add_child(first)
	first.set_physics_process(false)
	var monitor: GoapRuntimeMonitor = load("res://addons/goap/runtime/goap_runtime_monitor.tscn").instantiate()
	monitor.show_on_ready = false
	scene.add_child(monitor)
	var metrics: GoapPerformanceMonitor = monitor.performance
	metrics.get_node("Body/Settings/Console").button_pressed = false
	check(monitor.tabs.get_tab_count() == 2, "default monitor provides Performance and GOAP")
	check(metrics.agent_count == 1, "late monitor discovers an existing ordinary Agent")
	var inspector := root.get_node_or_null("GoapInspector")
	var view: Control = inspector.goap_debugger if inspector != null else monitor._local_debugger
	check(view.agent_option_button.item_count == 1, "inspector discovers the existing Agent")
	GoapPlanningScheduler.for_tree(self).enqueue(first)
	await finish_request(first)
	check(metrics.planning_count == 1 and first.current_plan != null, "ordinary Agent completion is measured automatically")
	for frame in 10:
		await process_frame
	check(metrics.planning_count == 1, "completed samples are not counted again on later frames")
	check(metrics.frame_count > 0, "scheduler frames are sampled")

	var second := make_agent()
	scene.add_child(second)
	second.set_physics_process(false)
	check(metrics.agent_count == 2 and view.agent_option_button.item_count == 2, "new Agents are discovered dynamically")
	GoapPlanningScheduler.for_tree(self).enqueue(second)
	await finish_request(second)
	check(metrics.planning_count == 2, "new Agent reports are measured")
	second.free()
	check(metrics.agent_count == 1 and view.agent_option_button.item_count == 1, "removed Agents leave both registries")

	var page := Label.new()
	page.text = "Game-specific status"
	var page_id := monitor.register_page(page, "My game")
	monitor.tabs.move_child(page, 0)
	monitor.show_tab(page_id)
	check(monitor.tabs.get_current_tab_control() == page, "custom page keeps its handle after reordering")
	monitor.detach_tab(page_id)
	check(monitor.page_windows.has(page_id), "custom page detaches")
	monitor.hide_monitor()
	check(not monitor.page_windows[page_id].visible, "hiding the monitor hides detached pages")
	monitor.show_tab(page_id)
	monitor.page_windows[page_id].close_requested.emit()
	check(page.get_parent() == monitor.tabs, "closing a detached page docks it")
	monitor.detach_tab(page_id)
	check(monitor.unregister_page(page_id) == page and page.get_parent() == null, "unregistering a floating extension returns ownership")
	check(not monitor.page_windows.has(page_id), "unregistering cleans up the floating window")
	page.free()
	monitor.show_tab(page_id)
	monitor.detach_tab(-1)
	check(monitor.unregister_page(999) == null, "invalid handles are harmless")

	monitor.detach_tab(0)
	first._discard_plan()
	first.request_replan()
	GoapPlanningScheduler.for_tree(self).enqueue(first)
	await finish_request(first)
	check(metrics.planning_count == 3, "automatic collection survives detaching the performance page")
	monitor.dock_tab(0)
	first._discard_plan()
	first.request_replan()
	GoapPlanningScheduler.for_tree(self).enqueue(first)
	await finish_request(first)
	check(metrics.planning_count == 4, "docking neither loses nor duplicates subscriptions")
	metrics.get_node("Body/Settings/Reset").pressed.emit()
	check(metrics.planning_count == 0 and metrics.frame_count == 0, "reset clears collected samples")

	first.goals.clear()
	first.request_replan()
	GoapPlanningScheduler.for_tree(self).enqueue(first)
	await finish_request(first)
	check(metrics.idle_count == 1 and metrics.planning_count == 0, "no-goal requests count separately")
	var unreachable := GoapGoal.new()
	unreachable.goal_state.set_state(&"unreachable", true)
	first._discard_plan()
	first.goals.assign([unreachable])
	first.request_replan()
	GoapPlanningScheduler.for_tree(self).enqueue(first)
	await finish_request(first)
	check(metrics.planning_count == 1, "failed searches also produce one completed sample")
	first.request_replan()
	GoapPlanningScheduler.for_tree(self).enqueue(first)
	first.cancel_planning()
	for frame in 3:
		await process_frame
	check(metrics.planning_count == 1, "cancelled requests are not completed samples")

	monitor.detach_tab(1)
	scene.free()
	await process_frame
	check(not is_instance_valid(metrics), "scene teardown frees metrics and detached pages")
	if inspector != null:
		check(not is_instance_valid(inspector.host), "scene teardown releases the embedded inspector")
		inspector.show_window()
		check(inspector.monitor.tabs.get_tab_count() == 2, "unhosted autoload opens the full generic monitor")
		inspector.monitor.performance.get_node("Body/Settings/Console").button_pressed = false
		var replacement: GoapRuntimeMonitor = load("res://addons/goap/runtime/goap_runtime_monitor.tscn").instantiate()
		replacement.show_on_ready = false
		root.add_child(replacement)
		check(inspector.host == replacement.inspector_page and inspector.monitor == null, "scene host replaces the fallback without duplicate windows")
		replacement.free()
		inspector.show_window()
		check(inspector.goap_debugger.get_parent() == inspector.monitor.inspector_page, "fallback can be recreated after another host leaves")
		inspector.monitor.performance.get_node("Body/Settings/Console").button_pressed = false
	print("Runtime monitor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()
