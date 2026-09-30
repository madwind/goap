extends SceneTree

var checks := 0
var failures := 0
var owned: Array[GoapAgent] = []


class CostAction extends GoapAction:
	var price := 1.0
	var delay_usec := 0
	var position := -1.0
	var distance_cost := false
	var callbacks_on_main := true
	var availability_calls := 0
	var availability_delay_usec := 0
	var performances := 0


	func get_cost_model() -> GDScript:
		return preload("res://tests/cost_models/test_cost.gd")


	func capture_context(agent: GoapAgent) -> Dictionary:
		callbacks_on_main = callbacks_on_main and OS.get_thread_caller_id() == OS.get_main_thread_id()
		return {
			"price": price,
			"position_after": position,
			"uses_position": distance_cost,
			"delay_usec": delay_usec,
			"require_worker": agent != null and agent.asynchronous_planning
		}


	func is_valid(_agent: GoapAgent) -> bool:
		availability_calls += 1
		if availability_delay_usec > 0:
			OS.delay_usec(availability_delay_usec)
		return true


	func perform(_agent: GoapAgent, _delta: float) -> Status:
		performances += 1
		return Status.RUNNING


class RankedGoal extends GoapGoal:
	var priority := 1.0


	func get_priority(_state: GoapWorldState) -> float:
		return priority


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BUDGET FAIL: " + description)


func action(
	id: String,
	pre: Dictionary[StringName, bool],
	effects: Dictionary[StringName, bool]
) -> CostAction:
	var item := CostAction.new()
	item.name = id
	item.preconditions = GoapWorldState.new(pre)
	item.effects = GoapWorldState.new(effects)
	return item


func goal(id: String, desired: Dictionary[StringName, bool], priority := 1.0) -> RankedGoal:
	var item := RankedGoal.new()
	item.name = id
	item.goal_state = GoapWorldState.new(desired)
	item.priority = priority
	return item


func agent(actions: Array[GoapAction], goals: Array[GoapGoal]) -> GoapAgent:
	var item := GoapAgent.new()
	item.actions = actions
	item.goals = goals
	item.init_goap()
	owned.append(item)
	return item


func ids(plan: GoapPlan) -> Array[String]:
	var result: Array[String] = []
	if plan != null:
		for item in plan.actions:
			result.append(item.get_id())
	return result


func pending(agents: Array[GoapAgent]) -> bool:
	return agents.any(
		func(
			item: GoapAgent
		) -> bool: return item._planning_requested or item._budget_request != null
	)


func cost_calls(agent: GoapAgent) -> int:
	var request := agent._budget_request
	if request != null and request.task_id == -1 and request.worker_data.get("evaluation") != null:
		return request.worker_data.evaluation.statistics.get("evaluated_actions", 0)
	return agent.planning_statistics.get("request", {}).get("evaluated_actions", 0)


func drain(scheduler: GoapPlanningScheduler, agents: Array[GoapAgent]) -> void:
	for frame in 5000:
		scheduler.process_budget()
		if not pending(agents):
			return
		await process_frame
	check(false, "requests finish within test deadline")


func cleanup(scheduler: GoapPlanningScheduler) -> void:
	for item in owned:
		item._exit_tree()
		item.free()
	owned.clear()
	scheduler._exit_tree()
	scheduler.free()


func run() -> void:
	test_continuations()
	await test_report_contract()
	await test_suspend_worker()
	await test_shared_budget()
	await test_preparation_budget()
	await test_workers_and_fallback()
	await test_cancel_and_execution()
	await test_goal_change_keeps_executing()
	await test_shutdown()
	print("GOAP budget tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_continuations() -> void:
	var far := action("A_Far", {}, { &"ready": true })
	far.position = 10
	var near := action("B_Near", {}, { &"ready": true })
	near.position = 2
	var finish := action("Finish", { &"ready": true }, { &"done": true })
	finish.distance_cost = true
	var planner := GoapPlanner.new([far, near, finish])
	planner.debug = true
	var world := GoapWorldState.new()
	var desired := GoapWorldState.new({ &"done": true })
	var expected := planner.find_plan(world, desired)
	var expected_trace := planner.search_tree.duplicate(true)
	var prepared := GoapPlanner.prepare_snapshot(planner.create_action_snapshot())
	var search := GoapSearch.begin({}, { &"done": true }, prepared, 10000, true)
	check(
		GoapPlanner.is_pure_data(search),
		"search continuation contains no scene or callback objects"
	)
	GoapSearch.advance(search, Time.get_ticks_usec() - 1)
	check(
		search.statistics.expanded_nodes == 0 and not search.done,
		"expired search slice pauses without exhausting node limit"
	)
	for step in 1000:
		if GoapSearch.advance(search, Time.get_ticks_usec() + 20):
			break
	check(
		search.done and search.statistics.search_complete,
		"search resumes across small time slices"
	)
	finish.delay_usec = 1500
	var evaluation := GoapEvaluation.new(
		GoapSearch.result(search),
		prepared.records,
		world.to_dictionary(),
		desired.to_dictionary(),
		{},
		planner.capture_cost_models()
	)
	var slices := 0
	while not evaluation.finished and slices < 1000:
		evaluation.advance(Time.get_ticks_usec() + 100)
		slices += 1
	check(slices > 1, "cost evaluation yields inside candidate sequences")
	check(
		evaluation.found and evaluation.best_action_indices.map(
			func(index: int) -> String: return prepared.records[index].id
		) == ids(expected) and evaluation.best_cost == expected.cost,
		"sliced evaluation preserves dynamic state and cheapest plan"
	)
	check(
		evaluation.search_result.trace == expected_trace,
		"slicing preserves selected trace and tie breaks"
	)
	check(evaluation.statistics.max_cost_callback_ms >= 1.0, "slow callbacks are observable")


func test_report_contract() -> void:
	var scheduler := GoapPlanningScheduler.new()
	var first := action("B", {}, { &"done": true })
	var second := action("A", {}, { &"done": true })
	var owner := agent([first, second], [goal("Done", { &"done": true })])
	owner.asynchronous_planning = false
	owner.request_replan()
	var request := GoapPlanningRequest.new(owner)
	var report := request.report()
	check(
		not report.request_finished and report.search_complete == null and report.phase == "preparing",
		"pending reports distinguish request progress from search completeness"
	)
	var planner := GoapPlanner.new(owner.actions)
	var expected := planner.find_plan(owner.world_state, owner.goals[0].goal_state)
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	report = owner.planning_statistics
	check(
		report.request_finished and report.search_complete and report.reason == "found",
		"successful request is finished with a complete search"
	)
	check(
		ids(owner.current_plan) == ids(expected) and owner.current_plan.actions[0] == second,
		"both preparation paths preserve stable order and original action identity"
	)
	owner.suspend()
	owner.max_planning_nodes = 0
	owner.resume()
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	report = owner.planning_statistics
	check(
		report.request_finished and not report.search_complete and report.reason == "node_limit",
		"node-limited request finishes without claiming search completeness"
	)
	owner.actions.append(first)
	owner.request_replan()
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	report = owner.planning_statistics
	check(
		report.request_finished and not report.search_complete and report.reason == "invalid_input",
		"duplicate action ID fails through shared snapshot validation"
	)
	check(planner.create_action_snapshot().size() == 2, "captured planner action list is isolated")
	planner = GoapPlanner.new(owner.actions)
	check(
		planner.find_plan(owner.world_state, owner.goals[0].goal_state) == null
		and planner.statistics.reason == "invalid_input",
		"synchronous path rejects the same duplicate ID"
	)
	owner.goals.clear()
	owner.request_replan()
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	check(
		owner.planning_statistics.request_finished and owner.planning_statistics.reason == "no_goal",
		"no-goal request reports completion"
	)
	cleanup(scheduler)


func test_suspend_worker() -> void:
	var scheduler := GoapPlanningScheduler.new()
	var work := action("Work", {}, { &"done": true })
	work.delay_usec = 2000
	var owner := agent([work], [goal("Done", { &"done": true })])
	owner.request_replan()
	scheduler.enqueue(owner)
	owner.suspend()
	scheduler.process_budget()
	check(
		scheduler.statistics.queued_agents == 0 and not owner.is_planning(),
		"suspend unregisters a request before its first scheduler slice"
	)
	owner.resume()
	owner.request_replan()
	scheduler.enqueue(owner)
	for frame in 100:
		scheduler.process_budget()
		if owner._budget_request != null and owner._budget_request.task_id != -1:
			break
	var obsolete := owner._budget_request
	check(
		obsolete != null and obsolete.task_id != -1,
		"suspension scenario has a dispatched worker"
	)
	owner.suspend()
	for frame in 1000:
		scheduler.process_budget()
		if scheduler.statistics.active_workers == 0:
			break
		await process_frame
	check(
		obsolete != null and obsolete.cancelled and scheduler.statistics.active_workers == 0,
		"suspend safely reclaims dispatched worker"
	)
	check(
		not owner.is_planning() and owner.current_plan == null and scheduler.statistics.queued_agents == 0,
		"cancelled worker cannot install a plan or requeue a suspended agent"
	)
	owner.resume()
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	check(
		owner.current_plan != null and owner.current_plan.actions[0] == work,
		"resume plans successfully after worker cancellation"
	)
	cleanup(scheduler)


func test_shared_budget() -> void:
	var scheduler := GoapPlanningScheduler.new()
	scheduler.frame_budget_ms = 0.5
	scheduler.slice_budget_ms = 0.1
	var actions: Array[CostAction] = []
	var batch: Array[GoapAgent] = []
	for index in 6:
		var item := action("Work", {}, { &"done": true })
		item.delay_usec = 2000
		actions.append(item)
		var owner := agent([item], [goal("Done", { &"done": true })])
		owner.asynchronous_planning = false
		owner.request_replan()
		scheduler.enqueue(owner)
		batch.append(owner)
	var overrun_seen := false
	var global_limit_held := true
	var frames := 0
	while pending(batch) and frames < 1000:
		var before := 0
		for item in batch:
			before += cost_calls(item)
		scheduler.process_budget()
		var after := 0
		for item in batch:
			after += cost_calls(item)
		global_limit_held = global_limit_held and after - before <= 1
		overrun_seen = overrun_seen or scheduler.statistics.overrun_ms > 0.5
		frames += 1
	check(
		global_limit_held,
		"one slow callback exhausts the shared frame budget, not a budget per agent"
	)
	check(overrun_seen, "non-preemptible callback reports a soft-budget overrun")
	check(
		frames >= 6 and not pending(batch),
		"fair scheduling finishes every agent over multiple frames"
	)
	check(
		batch.all(func(item: GoapAgent) -> bool: return item._current_plan != null),
		"all agents receive valid plans"
	)
	check(
		actions.all(func(item: CostAction) -> bool: return item.callbacks_on_main),
		"context capture stays on main thread"
	)
	cleanup(scheduler)


func test_workers_and_fallback() -> void:
	var scheduler := GoapPlanningScheduler.new()
	scheduler.frame_budget_ms = 0.3
	scheduler.max_worker_tasks = 2
	scheduler.worker_slice_ms = 0.1
	var batch: Array[GoapAgent] = []
	var available: Array[CostAction] = []
	for index in 8:
		var invalid := action("Invalid", {}, { &"bad": true })
		invalid.price = NAN
		var good := action("Good", {}, { &"good": true })
		var unused := action("Unused", {}, { &"unused": true })
		available.append_array([invalid, good, unused])
		var owner := agent(
			[invalid, good, unused],
			[
				goal("Missing", { &"missing": true }, 40),
				goal("Bad", { &"bad": true }, 30),
				goal("Good", { &"good": true }, 20),
				goal("Unused", { &"unused": true }, 10)
			]
		)
		owner.request_replan()
		scheduler.enqueue(owner)
		batch.append(owner)
	var peak := 0
	for frame in 5000:
		scheduler.process_budget()
		peak = maxi(peak, scheduler.statistics.peak_workers)
		if not pending(batch):
			break
		await process_frame
	check(
		peak > 0 and peak <= 2,
		"background search is enabled by default and respects global worker cap"
	)
	check(not pending(batch), "concurrent worker requests all complete")
	for owner in batch:
		check(
			owner.current_goal == owner.goals[
				2
			] and owner.planning_statistics.request.searched_goals == 3,
			"pending goals do not fall back until search and cost evaluation finish"
		)
	check(
		batch.all(
			func(item: GoapAgent) -> bool: return item.planning_statistics.evaluation_on_worker
		),
		"costs and cost effects run on workers"
	)
	check(
		batch.all(
			func(
				item: GoapAgent
			) -> bool: return item.planning_statistics.request.evaluated_actions == 2
		),
		"successful goal skips lower-priority evaluation"
	)
	check(
		available.all(func(item: CostAction) -> bool: return item.callbacks_on_main),
		"capture stays on main while models enforce worker execution"
	)
	cleanup(scheduler)


func test_preparation_budget() -> void:
	var scheduler := GoapPlanningScheduler.new()
	scheduler.frame_budget_ms = 0.3
	var available: Array[GoapAction] = []
	for index in 8:
		var item := action("Action%d" % index, {}, { &"done": true })
		item.availability_delay_usec = 1000
		available.append(item)
	var owner := agent(available, [goal("Done", { &"done": true })])
	owner.asynchronous_planning = false
	owner.request_replan()
	scheduler.enqueue(owner)
	scheduler.process_budget()
	var calls := 0
	for item: CostAction in available:
		calls += item.availability_calls
	check(
		calls <= 1 and owner.is_planning(),
		"action snapshot preparation yields between availability callbacks"
	)
	await drain(scheduler, [owner])
	check(
		owner._current_plan != null and not owner.is_planning(),
		"preparation resumes without dropping actions"
	)
	check(
		owner.planning_statistics.request.preparation_time_ms >= 8.0,
		"preparation callbacks count toward measured work and global budget"
	)
	cleanup(scheduler)


func test_cancel_and_execution() -> void:
	var scheduler := GoapPlanningScheduler.new()
	scheduler.frame_budget_ms = 0.2
	var work := action("Work", { &"ready": true }, { &"done": true })
	work.delay_usec = 1000
	var owner := agent([work], [goal("Done", { &"done": true })])
	owner.world_state.set_state(&"ready", true)
	owner.asynchronous_planning = false
	owner.request_replan()
	scheduler.enqueue(owner)
	for frame in 1000:
		scheduler.process_budget()
		if cost_calls(owner) > 0:
			break
	check(
		owner._budget_request != null and owner._current_plan == null,
		"unfinished evaluation is not installed early"
	)
	var obsolete := owner._budget_request
	owner.world_state.set_state(&"ready", false)
	await drain(scheduler, [owner])
	check(
		obsolete.cancelled and owner._current_plan == null,
		"generation change cancels evaluation without installing stale plan"
	)
	owner.world_state.set_state(&"ready", true)
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	check(owner._current_plan != null, "fresh generation resumes planning successfully")
	var current := owner._current_plan
	scheduler.frame_budget_ms = 0
	owner.request_replan()
	scheduler.enqueue(owner)
	owner._physics_process(0.1)
	scheduler.process_budget()
	check(
		owner._current_plan == current and owner.current_action == work,
		"valid current plan continues while budget is exhausted"
	)
	owner.world_state.set_state(&"ready", false)
	owner._physics_process(0.1)
	check(
		owner._current_plan == null and owner.current_action == null,
		"invalid action stops even while planning has no budget"
	)
	check(owner._planning_requested, "budget exhaustion leaves request pending")
	cleanup(scheduler)


func test_goal_change_keeps_executing() -> void:
	var scheduler := GoapPlanningScheduler.new()
	var old_action := action("Old", {}, { &"old_done": true })
	var new_action := action("New", {}, { &"new_done": true })
	var old_goal := goal("OldGoal", { &"old_done": true }, 20)
	var new_goal := goal("NewGoal", { &"new_done": true }, 10)
	var owner := agent([old_action, new_action], [old_goal, new_goal])
	owner.asynchronous_planning = false
	owner.request_replan()
	scheduler.enqueue(owner)
	await drain(scheduler, [owner])
	owner._physics_process(0.1)
	check(owner.current_action == old_action, "initial action starts")
	old_goal.priority = 0
	scheduler.frame_budget_ms = 0
	var before := old_action.performances
	owner._physics_process(0.1)
	scheduler.enqueue(owner)
	scheduler.process_budget()
	check(
		owner.is_planning() and owner.current_action == old_action
		and old_action.performances == before + 1,
		"goal change keeps the current action moving while planning is pending"
	)
	scheduler.frame_budget_ms = 0.2
	await drain(scheduler, [owner])
	check(
		owner.current_goal == new_goal and owner.current_plan != null
		and owner.current_action == null,
		"completed planning installs the replacement plan"
	)
	owner._physics_process(0.1)
	check(owner.current_action == new_action and new_action.performances == 1,
		"replacement action executes on the next physics tick")
	cleanup(scheduler)


func test_shutdown() -> void:
	var scheduler := GoapPlanningScheduler.new()
	var pending_agent := agent(
		[action("Work", {}, { &"done": true })],
		[goal("Done", { &"done": true })]
	)
	pending_agent.request_replan()
	scheduler.enqueue(pending_agent)
	for frame in 100:
		scheduler.process_budget()
		if pending_agent._budget_request != null and pending_agent._budget_request.task_id != -1:
			break
	var request := pending_agent._budget_request
	check(request != null and request.task_id != -1, "shutdown scenario has a dispatched worker")
	pending_agent._exit_tree()
	owned.erase(pending_agent)
	pending_agent.free()
	await drain(scheduler, [])
	check(request.cancelled, "agent removal cancels request without accessing freed agent")
	cleanup(scheduler)
	check(request.task_id == -1, "scheduler shutdown joins outstanding worker slices")


func _initialize() -> void:
	run.call_deferred()
