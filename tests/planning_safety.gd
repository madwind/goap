extends SceneTree

const SafeCost = preload("res://tests/cost_models/test_cost.gd")
const UnsafeCost = preload("res://tests/cost_models/unsafe_scene_cost.gd")
var checks := 0
var failures := 0


class ModelAction extends GoapAction:
	var model: GDScript = SafeCost
	var context: Dictionary = { "price": 3.0 }
	var captures := 0
	var captured_on_main := true


	func get_cost_model() -> GDScript:
		return model


	func capture_context(_agent: GoapAgent) -> Dictionary:
		captures += 1
		captured_on_main = captured_on_main and OS.get_thread_caller_id() == OS.get_main_thread_id()
		return context


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SAFETY FAIL: " + message)


func run() -> void:
	test_diagnostics()
	test_capture()
	await test_workers()
	await test_rejection()
	await test_impure_worker_output()
	print(
		"GOAP planning safety: %d checks, %d failures (intentional warnings above)" % [
			checks,
			failures
		]
	)
	quit(1 if failures else 0)


func test_diagnostics() -> void:
	check(GoapPlanningSafety.inspect_model(SafeCost).is_empty(), "pure static cost model accepted")
	var issues := GoapPlanningSafety.inspect_model(UnsafeCost)
	check(
		issues.size() >= 2 and issues[0].contains("unsafe_scene_cost.gd:6"),
		"scene access reports script and source line"
	)
	var safe := "extends GoapCostModel\n# get_tree() is forbidden\nstatic func get_cost(s, c):\n\tvar text = \"get_node('/root/Node')\"\n\treturn 12%5\n"
	check(
		GoapPlanningSafety.inspect_source(safe, "safe.gd").is_empty(),
		"comments, strings and arithmetic modulo do not trigger warnings"
	)
	for expression in [
		"get_tree()",
		"$Enemy",
		"%Enemy",
		"GameState.actor",
		"instance_from_id(1)",
		"target.global_position",
		"x.call('get_tree')",
		"load('res://helper.gd')"
	]:
		issues = GoapPlanningSafety.inspect_source(
			"extends GoapCostModel\nstatic func get_cost(s, c):\n\treturn " + expression,
			"bad.gd",
			["GameState"]
		)
		check(not issues.is_empty(), "warn for scene/global/dynamic access: " + expression)
	issues = GoapPlanningSafety.inspect_source(
		"extends GoapCostModel\nstatic var cached = {}\nstatic func helper():\n\treturn Engine.get_main_loop()",
		"helper.gd"
	)
	check(issues.size() >= 2, "scan helper functions and shared static state")
	var actor := Node.new()
	check(
		GoapPlanningSafety.impure_path(
			{ "nested": [{ "target": actor }] },
			"Action.context"
		).contains("Action.context[nested][0][target]"),
		"live object diagnostic identifies nested data path"
	)
	actor.free()


func test_impure_worker_output() -> void:
	var action := ModelAction.new()
	action.name = &"ImpureSimulation"
	action.effects.set_state(&"done", true)
	action.model = preload("res://tests/cost_models/impure_simulation_cost.gd")
	var planner := GoapPlanner.new([action])
	var models := planner.capture_cost_models()
	var work := GoapPlanningWork.begin(
		{},
		{ &"done": true },
		GoapPlanner.prepare_snapshot(planner.create_action_snapshot()),
		models,
		{},
		10000,
		false
	)
	var task := WorkerThreadPool.add_task(GoapPlanningWork.advance.bind(work))
	for frame in 1000:
		if WorkerThreadPool.is_task_completed(task):
			break
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	check(
		work.result.warnings.size() == 1 and not work.result.found,
		"impure simulation rejected and diagnostic returned from worker"
	)
	check(
		GoapPlanner.is_pure_data(work.result),
		"worker output contains no local objects or runtime references"
	)
	GoapPlanningWork.materialize(work.result, planner)
	check(
		planner.statistics.warnings[0].contains("ImpureSimulation.apply_cost_effect"),
		"main-thread result retains actionable worker diagnostic"
	)


func test_capture() -> void:
	var action := ModelAction.new()
	action.name = &"Capture"
	action.effects.set_state(&"done", true)
	action.context = { "price": 7.0, "nested": [{ "value": 1 }] }
	var entry := GoapPlanningSafety.capture(action, null)
	action.context.nested[0].value = 9
	check(entry.context.nested[0].value == 1, "captured data is isolated from runtime edits")
	check(
		entry.context.is_read_only() and entry.context.nested.is_read_only()
		and entry.context.nested[0].is_read_only(),
		"cost context is recursively read-only"
	)
	var planner := GoapPlanner.new([action])
	var plan := planner.find_plan(
		GoapWorldState.new(),
		GoapWorldState.new({ &"done": true }),
		{},
		{ "Capture": { "price": 2.0 } }
	)
	check(
		plan != null and plan.cost == 2.0 and plan.actions[0] == action,
		"synchronous callers can supply explicit cost contexts and receive runtime actions"
	)
	check(action.captures == 1, "explicit context avoids invoking scene capture with null agent")


func test_workers() -> void:
	for asynchronous in [false, true]:
		var action := ModelAction.new()
		action.name = &"Worker"
		action.effects.set_state(&"done", true)
		action.context = { "price": 4.0, "require_worker": asynchronous }
		var agent := GoapAgent.new()
		agent.asynchronous_planning = asynchronous
		agent.actions = [action]
		var goal := GoapGoal.new()
		goal.name = "Done"
		goal.goal_state.set_state(&"done", true)
		agent.goals = [goal]
		agent.init_goap()
		agent.request_replan()
		var scheduler := GoapPlanningScheduler.new()
		scheduler.enqueue(agent)
		for frame in 1000:
			scheduler.process_budget()
			if not agent.is_planning():
				break
			await process_frame
		check(
			agent._current_plan != null and agent._current_plan.cost == 4.0,
			"full worker search/cost evaluation produces expected plan"
		)
		check(
			agent.planning_statistics.evaluation_on_worker == asynchronous,
			"cost evaluation uses configured thread mode"
		)
		check(
			action.captures == 1 and action.captured_on_main,
			"context captured once on main thread"
		)
		check(
			agent._current_plan.actions[0] == action,
			"worker action IDs map back to original runtime action"
		)
		agent._exit_tree()
		agent.free()
		scheduler._exit_tree()
		scheduler.free()


func test_rejection() -> void:
	var actor := Node.new()
	for unsafe_scene in [false, true]:
		var action := ModelAction.new()
		action.name = &"BadScene" if unsafe_scene else &"BadSnapshot"
		action.effects.set_state(&"done", true)
		if unsafe_scene:
			action.model = UnsafeCost
		else:
			action.context = { "nested": [{ "target": actor }] }
		var agent := GoapAgent.new()
		agent.actions = [action]
		var goal := GoapGoal.new()
		goal.name = "Done"
		goal.goal_state.set_state(&"done", true)
		agent.goals = [goal]
		agent.init_goap()
		agent.request_replan()
		var scheduler := GoapPlanningScheduler.new()
		scheduler.enqueue(agent)
		for frame in 1000:
			scheduler.process_budget()
			if not agent.is_planning():
				break
			await process_frame
		check(
			agent._current_plan == null and agent.planning_statistics.get(
				"reason"
			) == "unsafe_cost_model",
			"unsafe request rejected before worker dispatch"
		)
		check(
			agent.planning_statistics.get("warning", "").contains(String(action.name)),
			"warning identifies offending action"
		)
		check(
			scheduler.statistics.peak_workers == 0,
			"unsafe scene access was never executed in worker"
		)
		agent._exit_tree()
		agent.free()
		scheduler._exit_tree()
		scheduler.free()
	actor.free()


func _initialize() -> void:
	run.call_deferred()
