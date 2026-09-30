extends SceneTree

const Behavior = preload("res://tests/diagnostics_action.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DIAGNOSTICS FAIL: " + message)


func make_agent() -> GoapAgent:
	var agent := GoapAgent.new()
	agent.actions.append(Behavior.new())
	agent.goals.append(preload("res://tests/diagnostics_goal.gd").new())
	agent.world_state = GoapWorldState.new({ &"done": false, &"ready": true })
	agent.asynchronous_planning = false
	agent.init_goap()
	return agent


func run() -> void:
	await test_decisions_and_events()
	test_session_history()
	test_remote_pause()
	test_observation_switching()
	test_complete_comparisons()
	print("GOAP diagnostics tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_decisions_and_events() -> void:
	var agent := make_agent()
	agent.actions.append(Behavior.new("Expensive", 10.0))
	agent.goals.append(preload("res://tests/diagnostics_goal.gd").new("Disabled", 0.0))
	agent.goals.append(preload("res://tests/diagnostics_goal.gd").new("Lower", 1.0))
	agent.request_replan()
	check(agent.take_diagnostic_events().is_empty(), "unobserved Agent records no events")
	agent.begin_diagnostics()
	agent.request_replan("test_request")
	var request := GoapPlanningRequest.new(agent)
	var scheduler := GoapPlanningScheduler.for_tree(self)
	for iteration in 100:
		request.advance(Time.get_ticks_usec() + 100000, scheduler)
		if request.finished:
			break
	check(request.finished and request.plan != null and is_equal_approx(request.plan.cost, 2.5), "GDScript cost model is used by real planner")
	var report := request.report()
	check(report.has("decisions"), "observed request records decision evidence")
	check(report.decisions.goals.any(func(item: Dictionary) -> bool: return item.id == "Disabled" and item.has("priority") and not item.has("goal_priority_threshold")),
		"goal decision reports use priority terminology")
	check(report.decisions.goals.any(func(item: Dictionary) -> bool: return item.id == "Disabled" and item.reason == "priority_disabled"), "zero Priority explanation recorded")
	check(report.decisions.goals.any(func(item: Dictionary) -> bool: return item.id == "Lower" and item.reason == "not_searched_higher_ranked_goal_succeeded"), "unsearched lower goal accurately explained")
	var comparisons: Array = report.decisions.comparisons[0].candidates
	check(comparisons.any(func(item: Dictionary) -> bool: return item.reason == "selected" and is_equal_approx(item.cost, 2.5)), "winning cost recorded")
	check(comparisons.any(func(item: Dictionary) -> bool: return item.reason in ["higher_cost", "higher cost"] and item.cost >= 10.0), "more expensive candidate or lower bound recorded")
	agent.world_state.set_state(&"ready", false)
	var events := agent.take_diagnostic_events()
	check(events.any(func(event: Dictionary) -> bool: return event.type == "facts_changed" and event.data.changes[0].fact == "ready"), "world change recorded with fact diff")
	check(events.any(func(event: Dictionary) -> bool: return event.type == "replan_requested" and event.data.reason == "world_state_changed"), "fact change links to replan")
	agent.world_state.set_state(&"ready", true)
	var action = agent.actions[0]
	action.fail = true
	agent._current_plan = GoapPlan.new()
	agent._current_plan.actions.append(action)
	agent.current_goal = agent.goals[0]
	agent._follow_plan(0.1)
	events = agent.take_diagnostic_events()
	var types: Array = events.map(func(event: Dictionary) -> String: return event.type)
	check(types.has("action_started") and types.has("action_stopped") and types.has("action_failed"), "failed execution records complete action lifecycle")
	check(types.find("action_started") < types.find("action_failed"), "failure occurs after start")
	check(events.any(func(event: Dictionary) -> bool: return event.type == "replan_requested" and event.data.reason == "action_failed"), "failure triggers explained replan")
	agent.world_state.set_state(&"ready", false)
	agent._current_plan = GoapPlan.new()
	agent._current_plan.actions.append(action)
	agent.current_goal = agent.goals[0]
	agent._follow_plan(0.1)
	events = agent.take_diagnostic_events()
	check(events.any(func(event: Dictionary) -> bool: return event.type == "action_failed" and event.data.reason == "preconditions" and event.data.missing.get(&"ready") == true), "failed precondition identifies the actual missing fact")
	agent.world_state.set_state(&"ready", true)
	action.preempt = true
	var stops: int = action.stops
	agent._current_plan = GoapPlan.new()
	agent._current_plan.actions.append(action)
	agent.current_goal = agent.goals[0]
	agent._follow_plan(0.1)
	events = agent.take_diagnostic_events()
	check(agent.is_suspended and action.stops == stops + 1 and not events.any(func(event: Dictionary) -> bool: return event.type == "action_succeeded"), "script lifecycle remains reentrant while diagnostics are enabled")
	agent.resume()
	agent.take_diagnostic_events()
	for index in 200:
		agent.record_diagnostic("test", { "index": index })
	events = agent.take_diagnostic_events()
	check(events.size() == 128 and agent.diagnostic_dropped == 72, "runtime event buffer bounded with dropped count")
	agent.end_diagnostics()
	agent.request_replan()
	check(agent.take_diagnostic_events().is_empty(), "stopping observation stops recording")
	request = GoapPlanningRequest.new(agent)
	for iteration in 100:
		request.advance(Time.get_ticks_usec() + 100000, scheduler)
		if request.finished:
			break
	check(not request.report().has("decisions") and not request.report().has("candidate_comparisons"), "unobserved planning omits detailed comparisons")
	agent.free()
	await process_frame


func test_session_history() -> void:
	var model := preload("res://addons/goap/debugger/goap_debug_session.gd").new()
	var pause_commands: Array = []
	model.command_requested.connect(func(message: String, data: Array) -> void:
		if message == "goap:set_paused":
			pause_commands.append(data))
	model.start()
	var view := preload("res://addons/goap/debugger/goap_remote_view.gd").new()
	root.add_child(view)
	view.add_session(0, model)
	check(not view.pause_button.disabled and view.pause_button.text == "Pause game",
		"connected Runtime tab exposes the pause control")
	view.pause_button.pressed.emit()
	check(pause_commands == [[true]], "editor pause control sends a command to the running session")
	model.receive("goap:performance", { "version": 2, "metrics": {}, "paused": true })
	check(model.paused and view.pause_button.text == "Resume game",
		"runtime pause state updates the editor control")
	view.pause_button.pressed.emit()
	check(pause_commands == [[true], [false]], "editor resume control sends the matching command")
	view.free()
	model.receive("goap:agents", { "version": 2, "agents": [{ "id": 123, "path": "/Agent" }] })
	model.observe(123)
	var events: Array[Dictionary] = []
	for index in 300:
		events.append({ "sequence": index, "type": "test", "generation": 1, "time_usec": index, "data": {} })
	model.receive("goap:events", { "version": 2, "agent_id": 123, "events": events })
	check(model.events.size() == 256 and model.events[0].sequence == 44, "editor history has a fixed bound")
	model.receive("goap:plan", { "version": 2, "agent_id": 124, "goal": "wrong" })
	check(model.snapshot.is_empty(), "late snapshots from previously observed Agent ignored")
	model.receive("goap:plan", { "version": 2, "agent_id": 123, "goal": "current" })
	check(model.snapshot.goal == "current", "selected Agent snapshot accepted")
	model.receive("goap:plan", { "version": 2, "agent_id": 123, "statistics": { "generation": 4 }, "decisions": { "comparisons": [{ "goal": "Finish" }] } })
	model.receive("goap:plan", { "version": 2, "agent_id": 123, "statistics": { "generation": 4 } })
	check(model.snapshot.statistics.decisions.comparisons[0].goal == "Finish", "editor retains one-shot planning results across live snapshots")
	model.receive("goap:plan", { "version": 2, "agent_id": 123, "statistics": { "generation": 5 } })
	check(not model.snapshot.statistics.has("decisions"), "new request clears old planning results")
	model.receive("goap:agents", { "version": 2, "agents": [] })
	check(model.selected_id == 0 and model.snapshot.is_empty(), "Agent destruction clears live selection")
	model.stop()
	check(model.events.is_empty() and model.agents.is_empty() and not model.paused,
		"disconnect releases session state")
	model.set_paused(true)
	check(pause_commands.size() == 2, "stopped sessions cannot pause a game")


func test_observation_switching() -> void:
	var inspector := preload("res://addons/goap/debugger/goap_debugger_autoload.gd").new()
	var first := GoapAgent.new()
	var second := GoapAgent.new()
	first.init_goap()
	second.init_goap()
	inspector._on_node_added(first)
	inspector._on_node_added(second)
	inspector._on_node_added(first)
	check(inspector.agents.size() == 2, "late discovery cannot register an Agent twice")
	inspector._capture_command("observe", [first.get_instance_id()])
	check(first.diagnostics_enabled and not second.diagnostics_enabled, "only selected Agent collects diagnostic data")
	inspector._capture_command("observe", [second.get_instance_id()])
	check(not first.diagnostics_enabled and second.diagnostics_enabled, "changing selection stops prior Agent collection")
	inspector._on_node_removed(second)
	check(inspector.observed == null and not second.diagnostics_enabled, "destruction releases observation")
	inspector._on_node_removed(first)
	first.free()
	second.free()
	inspector.free()


func test_remote_pause() -> void:
	var remote := preload("res://addons/goap/debugger/goap_debugger_autoload.gd").new()
	root.add_child(remote)
	check(remote.process_mode == Node.PROCESS_MODE_ALWAYS,
		"runtime debugger keeps processing while the game is paused")
	check(remote._capture_command("set_paused", [true]) and paused,
		"runtime pause command pauses the game tree")
	check(remote._capture_command("set_paused", [false]) and not paused,
		"runtime resume command restores the game tree")
	remote.free()


func test_complete_comparisons() -> void:
	var agent := make_agent()
	var winner := agent.goals[0]
	agent.goals.clear()
	for index in 130:
		agent.goals.append(preload("res://tests/diagnostics_goal.gd").new("Unreachable%03d" % index, 1000.0 - index, &"unreachable"))
	agent.goals.append(winner)
	for index in 50:
		agent.actions.append(Behavior.new("Variant%02d" % index, 1.0 if index == 49 else 100.0))
	agent.begin_diagnostics()
	agent.request_replan()
	var request := GoapPlanningRequest.new(agent)
	var scheduler := GoapPlanningScheduler.for_tree(self)
	for iteration in 100:
		request.advance(Time.get_ticks_usec() + 100000, scheduler)
		if request.finished:
			break
	check(request.finished and request.plan != null and request.plan.cost == 1.0, "large script action set still selects actual cheapest plan")
	var decisions: Dictionary = request.report().get("decisions", {})
	check(decisions.goals.size() <= 128 and decisions.comparisons.size() == 131, "every searched goal retains its computation results")
	check(decisions.goals.any(func(item: Dictionary) -> bool: return item.id == "Finish" and item.reason == "selected"), "winning goal retained even beyond goal sampling cap")
	var comparison: Dictionary = decisions.comparisons[-1]
	check(comparison.goal == "Finish" and comparison.candidates.size() == comparison.candidate_count and comparison.candidates.size() > 32, "every evaluated candidate is retained")
	var selected: Array = comparison.candidates.filter(func(item: Dictionary) -> bool: return item.reason == "selected")
	check(selected.size() == 1 and selected[0].actions == ["Variant49"], "exact winning candidate retained beyond candidate sampling cap")
	var view := preload("res://addons/goap/debugger/goap_remote_view.gd").new()
	get_root().add_child(view)
	view._render_decisions(decisions)
	var groups: TreeItem = view.cost_tree.get_root()
	check(groups.get_child_count() == decisions.comparisons.size(), "Runtime lists every searched goal")
	var plan_group: TreeItem = groups.get_child(groups.get_child_count() - 1)
	check(plan_group.get_child_count() == comparison.candidates.size(), "Runtime lists every computed plan")
	check(plan_group.get_child(0).get_text(0) == "Variant49" and plan_group.get_child(0).get_text(1) == "1.0", "Runtime shows cheapest plan first with its computed cost")
	var ordered: Array = view._sorted_candidates([
		{ "index": 0, "cost": 5.0, "reason": "higher_cost" },
		{ "index": 1, "cost": null, "reason": "invalid" },
		{ "index": 2, "cost": 2.0, "cost_is_lower_bound": true },
		{ "index": 3, "cost": 2.0, "reason": "higher_cost" },
		{ "index": 4, "cost": 2.0, "reason": "selected" },
	])
	check(ordered.map(func(item: Dictionary) -> int: return item.index) == [4, 3, 2, 0, 1], "equal exact costs precede lower bounds and invalid costs sort last")
	view.queue_free()
	agent.free()
