extends SceneTree

var checks := 0
var failures := 0
var agents: Array[GoapAgent] = []
var scheduler := GoapPlanningScheduler.new()


class TestAgent extends GoapAgent:
	var test_scheduler: GoapPlanningScheduler


	# Deterministic detached harness: drain the real scheduler before execution.
	func _follow_plan(delta: float) -> void:
		if not asynchronous_planning and is_planning():
			test_scheduler.enqueue(self)
			for frame in 1000:
				test_scheduler.process_budget()
				if not is_planning():
					break
		super._follow_plan(delta)


class TestAction extends GoapAction:
	var price := 1.0
	var result := Status.SUCCESS
	var starts := 0
	var stops := 0
	var performances := 0
	var position_after := -1.0
	var uses_position := false
	var available := true


	func is_valid(_agent: GoapAgent) -> bool:
		return available


	func get_cost_model() -> GDScript:
		return preload("res://tests/cost_models/test_cost.gd")


	func capture_context(owner_agent: GoapAgent) -> Dictionary:
		return {
			"price": price,
			"position_after": position_after,
			"uses_position": uses_position,
			"require_worker": owner_agent != null and owner_agent.asynchronous_planning
		}


	func start(_agent: GoapAgent) -> void:
		starts += 1


	func perform(_agent: GoapAgent, _delta: float) -> Status:
		performances += 1
		return result


	func stop(_agent: GoapAgent) -> void:
		stops += 1


class TestGoal extends GoapGoal:
	var priority := 1.0
	var valid := true


	func get_priority(_state: GoapWorldState) -> float:
		return priority


	func is_valid(_state: GoapWorldState) -> bool:
		return valid


class ParentAction extends GoapAction:
	func perform(owner_agent: GoapAgent, _delta: float) -> Status:
		owner_agent.actor.set_meta(&"planned", true)
		return Status.SUCCESS


class FixedCostAction extends GoapAction:
	func _get_cost() -> float:
		return 2.5


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func state(data: Dictionary[StringName, bool] = {}) -> GoapWorldState:
	return GoapWorldState.new(data)


func action(
	id: String,
	pre: Dictionary[StringName, bool],
	effects: Dictionary[StringName, bool],
	price := 1.0
) -> TestAction:
	var result := TestAction.new()
	result.name = id
	result.preconditions = state(pre)
	result.effects = state(effects)
	result.price = price
	return result


func goal(id: String, desired: Dictionary[StringName, bool], priority := 1.0) -> TestGoal:
	var result := TestGoal.new()
	result.name = id
	result.goal_state = state(desired)
	result.priority = priority
	return result


func agent(available: Array[GoapAction] = [], goals: Array[GoapGoal] = []) -> GoapAgent:
	var result := TestAgent.new()
	result.test_scheduler = scheduler
	result.asynchronous_planning = false
	result.actions = available
	result.goals = goals
	result.init_goap()
	agents.append(result)
	return result


func ids(plan: GoapPlan) -> Array[String]:
	var names: Array[String] = []
	if plan != null:
		for item in plan.actions:
			names.append(item.get_id())
	return names


func run() -> void:
	test_world_state()
	test_initial_world_state()
	test_regression()
	test_capacity_search()
	test_costs_and_determinism()
	await test_stable_tie_break()
	test_prepared_search()
	test_cached_preparation()
	test_random_static_domains()
	test_runtime()
	test_runtime_boundaries()
	await test_runtime_cache()
	await test_async()
	await test_lazy_goals()
	await test_initial_plan()
	await test_actor_ownership()
	await test_debugger_view()
	for item in agents:
		item._exit_tree()
		item.free()
	scheduler._exit_tree()
	scheduler.free()
	print("GOAP tests: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_initial_world_state() -> void:
	var configured := GoapAgent.new()
	configured.goap_script_folder = "res://tests/export_fixture"
	configured.init_goap()
	check(configured.world_state.size() == 0, "Agent starts without a manually authored world state file")
	configured.world_state.set_state(&"configured_true", false)
	configured.init_goap()
	check(configured.world_state.has_state(&"configured_true") and not configured.world_state.get_state(&"configured_true"), "reinitializing planner preserves an existing live fact")
	configured.free()
	var other := GoapAgent.new()
	other.init_goap("res://tests/export_fixture")
	check(other.world_state.size() == 0, "each Agent starts with its own empty observation")
	other.free()


func test_world_state() -> void:
	var data: Dictionary[StringName, bool] = { &"a": true }
	var a := state(data)
	data.a = false
	check(a.get_state(&"a"), "constructor copies its input")
	check(state().satisfies(state({ &"x": false })), "missing facts satisfy false")
	check(a.satisfies(state()), "empty requirements satisfied")
	check(a.conflicts(state({ &"a": false })), "overlapping opposite facts conflict")
	check(not a.conflicts(state({ &"b": false })), "unspecified constraints do not conflict")
	check(
		state({ &"a": true, &"b": false }).difference(a).size() == 0,
		"difference orientation"
	)
	check(
		state({ &"a": true, &"b": false }).get_key() == state(
			{ &"b": false, &"a": true }
		).get_key(),
		"canonical order"
	)
	check(
		state({ &"a=1|b": false }).get_key() != state({ &"a": true, &"b": false }).get_key(),
		"key escaping"
	)
	var events := [0]
	a.state_changed.connect(func() -> void: events[0] += 1)
	a.merge(state({ &"b": false }))
	a.merge(state({ &"b": false }))
	a.set_state(&"a", true)
	check(events[0] == 0, "adding false to missing facts does not signal a value change")
	check(not a.get_state(&"missing"), "missing fact reads false")
	var frozen := a.snapshot()
	a.merge(state({ &"merged_false": false }))
	a.set_state(&"set_false", false)
	check(not frozen.has(&"merged_false") and not frozen.has(&"set_false"), "old snapshot remains immutable")
	check(a.snapshot().has(&"merged_false") and a.snapshot().has(&"set_false"), "explicit false writes invalidate structural snapshot")
	check(events[0] == 0, "false writes preserve Boolean value without replanning")
	a.set_state(&"x", true)
	a.set_state(&"x", false)
	check(events[0] == 2, "Boolean transitions each signal once")
	check(state().get_key() != state({ &"x": false }).get_key(), "no constraint and negative constraint have different structural keys")
	check(not action("Unrelated", {}, { &"y": true }).is_relevant_to(state({ &"x": false })), "missing effect cannot establish a negative requirement")
	check(action("ClearX", {}, { &"x": false }).is_relevant_to(state({ &"x": false })), "explicit false effect establishes negative requirement")
	var copy := a.duplicate()
	copy.set_state(&"a", false)
	check(a.get_state(&"a"), "duplicate isolated")


func test_prepared_search() -> void:
	var prepare := action("Prepare", { &"blocked": false }, { &"ready": true })
	var finish := action("Finish", { &"ready": true }, { &"done": true, &"ready": false })
	var planner := GoapPlanner.new([prepare, finish])
	var prepared := GoapPlanner.prepare_snapshot(planner.create_action_snapshot())
	var original := prepared.duplicate(true)
	check(GoapPlanner.is_pure_data(prepared), "prepared search remains worker-safe pure data")
	for desired in [
		state({ &"ready": true }),
		state({ &"done": true }),
		state({ &"done": true, &"ready": true })
	]:
		var world := state({ &"blocked": false })
		var reused := GoapPlanner.search_prepared(
			world.to_dictionary(),
			desired.to_dictionary(),
			prepared,
			10000,
			true
		)
		var fresh := GoapPlanner.search_snapshot(
			world.to_dictionary(),
			desired.to_dictionary(),
			planner.create_action_snapshot(),
			10000,
			true
		)
		check(
			reused.candidates == fresh.candidates and reused.trace == fresh.trace,
			"prepared reuse preserves candidates and deterministic traces"
		)
	check(prepared == original, "searches do not mutate shared action records or index")
	var implicit_false := GoapPlanner.search_prepared({}, { &"done": true }, prepared)
	var explicit_false := GoapPlanner.search_prepared({ &"blocked": false }, { &"done": true }, prepared)
	check(not implicit_false.candidates.is_empty() and implicit_false.candidates == explicit_false.candidates, "prepared search treats missing facts as false")
	prepare.effects.set_state(&"ready", false)
	var old := GoapPlanner.search_prepared({ &"blocked": false }, { &"done": true }, prepared)
	check(not old.candidates.is_empty(), "prepared request is isolated from later action edits")
	check(
		planner.find_plan(state({ &"blocked": false }), state({ &"done": true })) == null,
		"next request rebuilds action effects and index"
	)
	var limited := GoapPlanner.search_prepared(
		{ &"blocked": false },
		{ &"done": true },
		prepared,
		1
	)
	check(not limited.statistics.search_complete, "prepared search retains node-limit reporting")


func test_capacity_search() -> void:
	var harvest := action("ZHarvest", {&"source": true}, {&"item_available": true})
	var pickup := action("ZPickup", {&"item_available": true, &"carrying": false},
		{&"has_item": true, &"item_available": false, &"carrying": true})
	var use_item := action("ZUse", {&"has_item": true}, {&"done": true, &"carrying": false})
	var available: Array[GoapAction] = [harvest, pickup, use_item]
	for index in 8:
		available.append(action("AStore%d" % index, {StringName("other%d" % index): true, &"carrying": true},
			{StringName("other%d" % index): false, &"carrying": false}))
	var planner := GoapPlanner.new(available)
	planner.max_nodes = 4
	check(ids(planner.find_plan(state({&"source": true}), state({&"done": true}))) == ["ZHarvest", "ZPickup", "ZUse"],
		"bounded search finds the direct acquisition chain before unrelated free-slot transitions")
	var impossible := action("Finish", {&"impossible": true, &"carrying": false}, {&"done": true})
	available.assign([impossible])
	for index in 8:
		available.append(action("Decoy%d" % index, {StringName("other%d" % index): true}, {&"carrying": false}))
	planner = GoapPlanner.new(available)
	check(planner.find_plan(state(), state({&"done": true})) == null
		and planner.statistics.expanded_nodes == 2 and planner.statistics.prune_reasons.get("unachievable", 0) > 0,
		"an unproducible unmet fact prunes the entire impossible branch")
	var disturb := action("Disturb", {}, {&"done": true, &"safe": false})
	var restore := action("Restore", {&"done": true}, {&"safe": true})
	planner = GoapPlanner.new([disturb, restore])
	check(ids(planner.find_plan(state({&"safe": true}), state({&"done": true, &"safe": true}))) == ["Disturb", "Restore"],
		"search still restores a fact that was initially satisfied")


func test_cached_preparation() -> void:
	var facts := state({ &"ready": true })
	var frozen := facts.snapshot()
	check(
		frozen.is_read_only() and is_same(frozen, facts.snapshot()),
		"unchanged facts reuse an immutable snapshot"
	)
	facts.set_state(&"ready", true)
	facts.merge(state({ &"ready": true }), false)
	check(is_same(frozen, facts.snapshot()), "no-op writes preserve the snapshot")
	facts.merge(state({ &"ready": false }), false)
	check(
		frozen.ready and not facts.snapshot().ready,
		"silent merge invalidates without changing old snapshots"
	)
	var mutable := facts.to_dictionary()
	mutable.ready = true
	check(not facts.snapshot().ready, "public dictionary copies remain isolated and mutable")

	var finish := action("Finish", {}, { &"done": true }, 2)
	var planner := GoapPlanner.new([finish])
	check(planner.prewarm(), "planner supports loading-time preparation")
	var prepared := planner.snapshot_cache.reuse(planner.create_action_snapshot())
	check(
		not prepared.is_empty() and prepared.is_read_only() and prepared.records.is_read_only()
		and prepared.records[0].is_read_only() and prepared.effect_index.values()[0].is_read_only(),
		"published cache and nested records/index are immutable"
	)
	var original := prepared.duplicate(true)
	var old_work := GoapPlanningWork.begin(
		{},
		{ &"done": true },
		prepared,
		planner.capture_cost_models(),
		{},
		10000,
		false
	)
	finish.price = 7
	var plan := planner.find_plan(state(), state({ &"done": true }))
	check(plan != null and plan.cost == 7, "warm planning captures updated dynamic costs")
	check(
		is_same(prepared, planner.snapshot_cache.reuse(planner.create_action_snapshot())),
		"repeated planning reuses the effect index"
	)
	finish.preconditions.set_state(&"ready", true)
	check(
		planner.find_plan(state(), state({ &"done": true })) == null,
		"precondition edits invalidate cached definitions"
	)
	check(
		planner.find_plan(state({ &"ready": true }), state({ &"done": true })) != null,
		"warm planning uses the current world"
	)
	finish.preconditions = state()
	check(
		planner.find_plan(state(), state({ &"done": true })) != null,
		"replacing the precondition object invalidates the cache"
	)
	finish.effects.merge(state({ &"done": false }), false)
	check(
		planner.find_plan(state(), state({ &"done": true })) == null,
		"silent effect edits rebuild the index"
	)
	finish.effects = state({ &"done": true })
	finish.name = &"Renamed"
	check(
		ids(planner.find_plan(state(), state({ &"done": true }))) == ["Renamed"],
		"renamed actions refresh cached IDs"
	)
	check(prepared == original, "new requests never modify previously published data")
	GoapPlanningWork.advance(old_work)
	check(
		old_work.result.found and old_work.result.statistics.cost == 2,
		"old work retains its original definitions and cost context after cache replacement"
	)
	var replacement := action("Alternative", {}, { &"done": true }, 1)
	planner.actions.append(replacement)
	check(
		ids(planner.find_plan(state(), state({ &"done": true }))) == ["Alternative"],
		"adding an action rebuilds the cached set"
	)
	planner.actions.reverse()
	check(
		planner.find_plan(state(), state({ &"done": true })).actions[0] == replacement,
		"reordering actions preserves live action index mapping"
	)
	planner.actions.erase(replacement)
	check(
		ids(planner.find_plan(state(), state({ &"done": true }))) == ["Renamed"],
		"removed actions are excluded from the next index"
	)
	planner.actions.append(finish)
	check(
		not planner.prewarm() and planner.find_plan(state(), state({ &"done": true })) == null,
		"warm cache does not bypass duplicate ID validation"
	)
	planner.actions.clear()
	check(
		planner.prewarm() and planner.find_plan(state(), state({ &"done": true })) == null,
		"empty action sets replace older caches"
	)


func test_runtime_cache() -> void:
	for asynchronous in [false, true]:
		var first := action("A", {}, { &"done": true }, 1)
		var second := action("B", {}, { &"done": true }, 2)
		var owner := agent([first, second], [goal("Done", { &"done": true })])
		owner.asynchronous_planning = asynchronous
		check(owner.prewarm_planning(), "agent supports explicit prewarming")
		var probe := GoapPlanner.new(owner.actions)
		var prepared := owner.planning_cache.reuse(probe.create_action_snapshot())
		owner.request_replan()
		await wait_for_planning(owner)
		check(
			ids(owner.current_plan) == ["A"] and is_same(
				prepared,
				owner.planning_cache.reuse(probe.create_action_snapshot())
			),
			"runtime requests reuse the prewarmed definitions and index"
		)
		owner._discard_plan()
		first.price = 3
		owner.request_replan()
		await wait_for_planning(owner)
		check(ids(owner.current_plan) == ["B"], "cached runtime requests recapture costs")
		owner._discard_plan()
		second.available = false
		owner.request_replan()
		await wait_for_planning(owner)
		check(
			ids(owner.current_plan) == ["A"],
			"availability changes invalidate the active action set"
		)
		owner._discard_plan()
		first.effects.set_state(&"done", false)
		owner.request_replan()
		await wait_for_planning(owner)
		check(owner.current_plan == null, "runtime definition edits invalidate the effect index")
		second.available = true
		owner.request_replan()
		await wait_for_planning(owner)
		check(ids(owner.current_plan) == ["B"], "re-enabled actions return to the index")


func wait_for_planning(test: GoapAgent) -> void:
	for frame in 300:
		scheduler.enqueue(test)
		scheduler.process_budget()
		if not test.is_planning():
			return
		await process_frame
	check(false, "planning completed within the test deadline")


func test_lazy_goals() -> void:
	for asynchronous in [false, true]:
		var invalid := action("Invalid", {}, { &"invalid": true }, NAN)
		var good := action("Good", {}, { &"good": true })
		var unused := action("Unused", {}, { &"unused": true })
		var goals: Array[GoapGoal] = [
			goal("Unreachable", { &"missing": true }, 40),
			goal("InvalidCost", { &"invalid": true }, 30),
			goal("GoodGoal", { &"good": true }, 20),
			goal("UnusedGoal", { &"unused": true }, 10)
		]
		var test := agent([invalid, good, unused], goals)
		test.asynchronous_planning = asynchronous
		test.request_replan()
		scheduler.enqueue(test)
		await wait_for_planning(test)
		check(
			test.current_goal == goals[2],
			"lazy goals fall back after unreachable and invalid-cost goals"
		)
		var totals: Dictionary = test.planning_statistics.request
		check(
			totals.searched_goals == 3 and totals.expanded_nodes == 5 and totals.candidate_count == 2,
			"request totals cover attempted goals and exclude lower-priority searches"
		)
		check(totals.evaluated_actions == 2, "only attempted goals run cost callbacks")
		check(
			test.planning_statistics.evaluation_on_worker == asynchronous,
			"cost evaluation follows configured thread mode"
		)
		check(
			totals.planning_time_ms >= totals.search_time_ms + totals.evaluation_time_ms,
			"request timing includes preparation"
		)
		var first := action("First", {}, { &"missing": true })
		test.actions.append(first)
		test._discard_plan()
		test.request_replan()
		scheduler.enqueue(test)
		await wait_for_planning(test)
		check(
			test.current_goal == goals[0] and test.planning_statistics.request.searched_goals == 1,
			"fresh request sees added actions and stops after highest-priority success"
		)
		check(
			test.planning_statistics.request.evaluated_actions == 1,
			"successful first goal skips all later evaluation"
		)
		check(
			test._budget_request == null,
			"finished request releases prepared data and candidates"
		)

	var stale := agent(
		[action("Good", { &"ready": true }, { &"good": true })],
		[
			goal("Missing", { &"missing": true }, 30),
			goal("Good", { &"good": true }, 20),
			goal("Unused", { &"unused": true }, 10)
		]
	)
	stale.asynchronous_planning = true
	stale.world_state.set_state(&"ready", true)
	scheduler.enqueue(stale)
	for frame in 300:
		scheduler.process_budget()
		if stale._budget_request != null and stale._budget_request.goal_index == 1:
			break
		await process_frame
	var obsolete := stale._budget_request
	check(
		obsolete != null and obsolete.goal_index == 1,
		"async failure advances only to the next goal"
	)
	stale.world_state.set_state(&"ready", false)
	await wait_for_planning(stale)
	check(
		obsolete.cancelled and stale._current_plan == null,
		"generation change during fallback discards stale result"
	)


func test_regression() -> void:
	var planner := GoapPlanner.new()
	check(planner.find_plan(state(), state()) != null, "already-satisfied goal gives empty plan")
	check(planner.find_plan(state(), state({ &"x": true })) == null, "no actions is safe")
	var chop := action("Chop", {}, { &"wood": true })
	var fire := action("Fire", { &"wood": true }, { &"fire": true })
	var hunt := action("Hunt", {}, { &"meat": true })
	var eat := action("Eat", { &"fire": true, &"meat": true }, { &"hungry": false })
	planner = GoapPlanner.new([eat, fire, hunt, chop])
	check(planner.find_plan(state(), state({ &"hungry": false })).actions.is_empty(), "missing hunger already satisfies not hungry")
	var initial := state({ &"hungry": true })
	var plan := planner.find_plan(initial, state({ &"hungry": false }))
	check(
		plan != null and plan.actions.size() == 4 and plan.is_valid_from(initial),
		"branching dependencies produce executable sequence"
	)
	check(plan.cost == 4, "sum of action costs")
	plan = planner.find_plan(state({ &"wood": true, &"hungry": true }), state({ &"hungry": false }))
	check(plan != null and plan.actions.size() == 3, "partially satisfied preconditions")
	var destructive := action("DestroyB", {}, { &"a": true, &"b": false })
	planner = GoapPlanner.new([destructive])
	check(
		planner.find_plan(state({ &"b": true }), state({ &"a": true, &"b": true })) == null,
		"preserve initially satisfied goals against destructive effects"
	)
	var conflicting := action("NeedsNotB", { &"b": false }, { &"a": true })
	planner = GoapPlanner.new([conflicting])
	check(
		planner.find_plan(state(), state({ &"a": true, &"b": true })) == null,
		"preconditions cannot conflict with remaining requirements"
	)
	var repair := action("RepairB", { &"a": true }, { &"b": true })
	planner = GoapPlanner.new([repair, destructive])
	plan = planner.find_plan(state({ &"b": true }), state({ &"a": true, &"b": true }))
	check(
		ids(plan) == ["DestroyB", "RepairB"],
		"restore an initially satisfied fact after destruction"
	)
	var a := action("A", { &"b": true }, { &"a": true })
	var b := action("B", { &"c": true }, { &"b": true })
	var c := action("C", { &"a": true }, { &"c": true })
	planner = GoapPlanner.new([a, b, c])
	planner.debug = true
	check(
		planner.find_plan(state(), state({ &"a": true })) == null,
		"cycle terminates without recursion limit"
	)
	check(
		planner.statistics.pruned_nodes > 0 and planner.statistics.search_complete,
		"cycle pruning recorded"
	)
	check(not planner.search_tree.is_empty(), "debug search trace available")
	planner.debug = false
	planner.find_plan(state(), state({ &"a": true }))
	check(planner.search_tree.is_empty(), "production does not retain debug tree")
	planner.max_nodes = 1
	planner.find_plan(state(), state({ &"a": true }))
	check(
		not planner.statistics.search_complete and planner.statistics.reason == "node_limit",
		"search truncation is explicit"
	)
	var relevant := action("Relevant", {}, { &"z": true })
	check(
		relevant.is_relevant_to(state({ &"a": true, &"z": true })),
		"relevance examines all facts"
	)


func test_costs_and_determinism() -> void:
	var scripted_fixed := FixedCostAction.new()
	scripted_fixed.effects = state({ &"scripted": true })
	check(
		GoapPlanner.new([scripted_fixed]).find_plan(state(), state({ &"scripted": true })).cost == 2.5,
		"action script declares fixed cost"
	)
	var fixed := GoapAction.new()
	fixed.name = &"Fixed"
	fixed.effects = state({ &"fixed": true })
	check(
		GoapPlanner.new([fixed]).find_plan(state(), state({ &"fixed": true })).cost == 1.0,
		"base action defaults to fixed cost 1"
	)
	fixed.cost = 4.0
	var fixed_planner := GoapPlanner.new([fixed])
	check(
		fixed_planner.find_plan(state(), state({ &"fixed": true })).cost == 4.0,
		"base action uses its fixed cost"
	)
	fixed.cost = 2.0
	check(
		fixed_planner.find_plan(state(), state({ &"fixed": true })).cost == 2.0,
		"new planning request captures edited fixed cost"
	)
	for invalid_cost in [-1.0, INF, NAN]:
		fixed.cost = invalid_cost
		check(
			fixed_planner.find_plan(state(), state({ &"fixed": true })) == null,
			"invalid fixed cost rejected"
		)
	var dynamic := action("Dynamic", {}, { &"dynamic": true }, 3.0)
	dynamic.cost = 99.0
	check(
		GoapPlanner.new([dynamic]).find_plan(state(), state({ &"dynamic": true })).cost == 3.0,
		"dynamic model overrides action fixed cost"
	)
	var expensive := action("Expensive", {}, { &"x": true }, 10)
	var cheap := action("Cheap", {}, { &"x": true }, 2)
	var planner := GoapPlanner.new([expensive, cheap])
	planner.debug = true
	check(
		ids(planner.find_plan(state(), state({ &"x": true }))) == ["Cheap"],
		"lower-cost path to same state preserved"
	)
	check(
		planner.statistics.get("pruned_candidates", 0) > 0,
		"nonnegative forward-cost bound prunes expensive candidates"
	)
	check(
		planner.search_tree.any(
			func(entry: Dictionary) -> bool: return entry.reason == "higher cost"
		),
		"debug trace explains cost pruning"
	)
	var first := action("A", {}, { &"x": true }, 2)
	planner = GoapPlanner.new([cheap, first])
	check(ids(planner.find_plan(state(), state({ &"x": true }))) == ["A"], "stable ID tie break")
	var reversed := GoapPlanner.new([first, cheap])
	check(
		ids(planner.find_plan(state(), state({ &"x": true }))) == ids(
			reversed.find_plan(state(), state({ &"x": true }))
		),
		"independent of action input order"
	)
	var free := action("Free", {}, { &"y": true }, 0)
	var two := action("Two", { &"y": true }, { &"x": true }, 2)
	planner = GoapPlanner.new([free, two, cheap])
	check(
		ids(planner.find_plan(state(), state({ &"x": true }))) == ["Cheap"],
		"fewer actions wins equal cost"
	)
	var alpha := action("Alpha", {}, { &"ready": true }, 0)
	var beta := action("Beta", { &"ready": true }, { &"x": true }, 2)
	var direct := action("ZDirect", {}, { &"x": true }, 2)
	planner = GoapPlanner.new([alpha, beta, direct])
	check(ids(planner.find_plan(state(), state({ &"x": true }))) == ["ZDirect"],
		"equal-cost plans prefer fewer actions before IDs")
	var near := action("Near", {}, { &"ready": true }, 3)
	near.position_after = 1
	var far := action("Far", {}, { &"ready": true }, 1)
	far.position_after = 100
	var finish := action("Finish", { &"ready": true }, { &"done": true })
	finish.uses_position = true
	planner = GoapPlanner.new([near, far, finish])
	var snapshot := { "position": 9.0, "nested": { "value": 1 } }
	var plan := planner.find_plan(state(), state({ &"done": true }), snapshot)
	check(
		ids(plan) == ["Near", "Finish"] and plan.cost == 4,
		"forward dynamic cost keeps distinct paths through same Boolean state"
	)
	check(snapshot.position == 9, "cost evaluation isolates initial snapshot")
	for bad_cost in [-1.0, INF, NAN]:
		var bad := action("Bad", {}, { &"x": true }, bad_cost)
		check(
			GoapPlanner.new([bad]).find_plan(state(), state({ &"x": true })) == null,
			"invalid cost rejected"
		)
	planner = GoapPlanner.new([cheap, cheap])
	check(planner.find_plan(state(), state({ &"x": true })) == null, "duplicate IDs rejected")
	check(
		not GoapPlanner.is_pure_data({ "nested": [GoapAction.new()] }),
		"nested live objects rejected in snapshots"
	)


func test_stable_tie_break() -> void:
	for asynchronous in [false, true]:
		var wood := action("ZWood", {}, { &"wood": true })
		var stone := action("AStone", {}, { &"stone": true })
		var craft := action("Craft", { &"wood": true, &"stone": true }, { &"weapon": true })
		var owner := TestAgent.new()
		owner.test_scheduler = scheduler
		owner.asynchronous_planning = asynchronous
		owner.actions = [wood, stone, craft]
		owner.goals = [goal("Weapon", { &"weapon": true })]
		owner.init_goap()
		agents.append(owner)
		owner.begin_diagnostics()
		owner.request_replan()
		await wait_for_planning(owner)
		check(ids(owner.current_plan) == ["AStone", "ZWood", "Craft"]
			and owner.current_plan.cost == 3.0,
			"equal-cost plans use stable action IDs")
		var comparisons: Array = owner.planning_statistics.get("decisions", {}).get("comparisons", [])
		var selected: Array = comparisons[0].candidates.filter(
			func(entry: Dictionary) -> bool: return entry.reason == "selected"
		) if not comparisons.is_empty() else []
		check(selected.size() == 1 and selected[0].actions == ["AStone", "ZWood", "Craft"],
			"diagnostics mark the stable sequence")
		owner._discard_plan()
		owner.actions.reverse()
		owner.request_replan()
		await wait_for_planning(owner)
		check(ids(owner.current_plan) == ["AStone", "ZWood", "Craft"],
			"action registration order does not change the tie result")
		owner._discard_plan()
		var direct := action("Direct", {}, { &"weapon": true }, 3)
		owner.actions.append(direct)
		owner.request_replan()
		await wait_for_planning(owner)
		check(ids(owner.current_plan) == ["Direct"],
			"shorter equal-cost plan wins before action IDs")


## Independent forward Dijkstra oracle on small finite Boolean domains.
func test_random_static_domains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 841031
	var keys: Array[StringName] = [&"a", &"b", &"c"]
	for trial in 100:
		var available: Array[GoapAction] = []
		for index in 6:
			var pre: Dictionary[StringName, bool] = {}
			var effects: Dictionary[StringName, bool] = {}
			for key in keys:
				if rng.randf() < 0.35:
					pre[key] = rng.randf() < 0.5
				if rng.randf() < 0.5:
					effects[key] = rng.randf() < 0.5
			available.append(action("action%d" % index, pre, effects, rng.randi_range(0, 5)))
		var initial := state()
		var desired := state()
		for key in keys:
			if rng.randf() < 0.7:
				initial.set_state(key, rng.randf() < 0.5)
			if rng.randf() < 0.7:
				desired.set_state(key, rng.randf() < 0.5)
		var expected := forward_cost(initial, desired, available)
		var planner := GoapPlanner.new(available)
		var plan := planner.find_plan(initial, desired)
		check(planner.statistics.search_complete, "random domain search complete %d" % trial)
		check(
			(plan == null and is_inf(expected)) or (
				plan != null and plan.cost == expected and plan.is_valid_from(initial)
			),
			"forward oracle agreement %d" % trial
		)


func forward_cost(
	initial: GoapWorldState,
	desired: GoapWorldState,
	available: Array[GoapAction]
) -> float:
	var frontier: Array = [{ "state": initial, "cost": 0.0 }]
	var best := { initial.get_key(): 0.0 }
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.cost < b.cost)
		var entry: Dictionary = frontier.pop_front()
		var facts: GoapWorldState = entry.state
		if facts.satisfies(desired):
			return entry.cost
		for item in available:
			if facts.satisfies(item.preconditions):
				var next := facts.duplicate()
				next.merge(item.effects, false)
				var cost: float = entry.cost + (item as TestAction).price
				if cost < best.get(next.get_key(), INF):
					best[next.get_key()] = cost
					frontier.append({ "state": next, "cost": cost })
	return INF


func test_runtime() -> void:
	var empty := agent()
	empty.request_replan()
	empty._physics_process(0.1)
	check(empty._current_plan == null, "no goals safely idle")
	var run := action("Run", {}, { &"done": true })
	run.result = GoapAction.Status.RUNNING
	var low := goal("Low", { &"done": true }, 10)
	var high := goal("HighUnreachable", { &"impossible": true }, 100)
	var test := agent([run], [low, high])
	test.request_replan()
	test._physics_process(0.1)
	check(test.current_goal == low, "unreachable high priority falls back")
	check(run.starts == 1 and run.performances == 1 and run.stops == 0, "start once then running")
	test._physics_process(0.1)
	check(run.starts == 1 and run.performances == 2, "running does not restart")
	var other := action("Other", {}, { &"other": true })
	other.result = GoapAction.Status.RUNNING
	var other_goal := goal("OtherGoal", { &"other": true }, 9)
	test.actions.append(other)
	test.goals.append(other_goal)
	test.request_replan()
	test._physics_process(0.1)
	check(test.current_goal == low, "lower-priority goal does not preempt")
	other_goal.priority = 11
	test.request_replan()
	test._physics_process(0.1)
	check(
		test.current_goal == other_goal and run.stops == 1,
		"higher-priority goal preempts with cleanup"
	)
	other.result = GoapAction.Status.FAILURE
	test._physics_process(0.1)
	check(
		test._current_plan == null and test._planning_requested and other.stops == 1,
		"action failure discards and requests replanning"
	)
	other_goal.valid = false
	run.result = GoapAction.Status.SUCCESS
	test._physics_process(0.1)
	check(
		test.world_state.get_state(&"done") and run.stops == 2,
		"success applies effects and stops"
	)
	test._physics_process(0.1)
	check(test._current_plan == null, "completed goals are not repeatedly selected")
	var prep := action("Prep", {}, { &"ready": true })
	var end := action("End", { &"ready": true }, { &"end": true })
	end.result = GoapAction.Status.RUNNING
	var invalidated := agent([prep, end], [goal("EndGoal", { &"end": true })])
	invalidated.request_replan()
	invalidated._physics_process(0.1)
	invalidated._physics_process(0.1)
	invalidated.world_state.set_state(&"ready", false)
	invalidated._physics_process(0.1)
	check(
		end.stops == 1 and prep.performances == 2,
		"world changes invalidate remaining preconditions and replan"
	)
	var gather := action("Gather", { &"source": true }, { &"item": true })
	gather.result = GoapAction.Status.RUNNING
	var use_gathered := action("UseGathered", { &"item": true }, { &"served": true })
	var use_ground := action("UseGround", { &"ground": true }, { &"served": true })
	use_ground.result = GoapAction.Status.RUNNING
	var reactive := agent([gather, use_gathered, use_ground], [goal("Serve", { &"served": true })])
	reactive.world_state.set_state(&"source", true)
	reactive.request_replan()
	reactive._physics_process(0.1)
	check(reactive.current_action == gather, "current goal starts with the available gathering route")
	reactive.world_state.set_state(&"unrelated", true)
	reactive._physics_process(0.1)
	check(reactive.current_action == gather and gather.starts == 1 and gather.stops == 0,
		"an unchanged route keeps its running action after replanning")
	reactive.world_state.set_state(&"ground", true)
	reactive._physics_process(0.1)
	check(reactive.current_action == use_ground and gather.stops == 1,
		"a world change replans the current goal and switches to the new route")


func test_async() -> void:
	var item := action("Async", { &"ready": true }, { &"done": true })
	item.result = GoapAction.Status.RUNNING
	var test := agent([item], [goal("AsyncGoal", { &"done": true })])
	test.asynchronous_planning = true
	test.world_state.set_state(&"ready", true)
	scheduler.enqueue(test)
	scheduler.process_budget()
	var obsolete := test._budget_request
	var generation := test._generation
	test.world_state.set_state(&"ready", false)
	check(test._generation > generation, "world change invalidates in-flight generation")
	await wait_for_planning(test)
	check(obsolete.cancelled and test._current_plan == null, "stale worker result discarded")
	test.world_state.set_state(&"ready", true)
	await wait_for_planning(test)
	check(test._current_plan != null, "fresh asynchronous result installed")
	var fresh := test._current_plan
	check(
		not obsolete.is_current() and test._current_plan == fresh,
		"old request cannot become current again"
	)


func test_runtime_boundaries() -> void:
	var item := action("Task", {}, { &"done": true })
	item.result = GoapAction.Status.RUNNING
	var wanted := goal("Goal", { &"done": true }, 0)
	var target := agent([item], [wanted])
	target.request_replan()
	target._physics_process(0.1)
	check(target._current_plan == null, "zero priority ignored")
	wanted.priority = 1
	item.available = false
	target.debug = true
	target.request_replan()
	target._physics_process(0.1)
	check(target._current_plan == null, "debug recording cannot bypass runtime availability")
	item.available = true
	target.request_replan()
	target._physics_process(0.1)
	wanted.valid = false
	target._physics_process(0.1)
	check(
		target._current_plan == null and item.stops == 1,
		"invalid goal stops current action without waiting for world signal"
	)
	wanted.valid = true
	var duplicate := goal("Goal", { &"other": true })
	target.goals.append(duplicate)
	target.request_replan()
	target._physics_process(0.1)
	check(
		target.planning_statistics.reason == "duplicate_goal_id",
		"duplicate goal IDs rejected deterministically"
	)
	target.goals.erase(duplicate)


func test_initial_plan() -> void:
	var item := GoapAction.new()
	item.name = &"Initial"
	item.effects.set_state(&"done", true)
	var test := GoapAgent.new()
	test.actions = [item]
	test.goals = [goal("InitialGoal", { &"done": true })]
	root.add_child(test)
	test.set_physics_process(false)
	check(test._planning_requested, "ready requests initial plan without state signal")
	for frame in 300:
		test._physics_process(0.1)
		if test.world_state.get_state(&"done"):
			break
		await process_frame
	check(test.world_state.get_state(&"done"), "initial plan executes")
	test.queue_free()
	await process_frame


func test_actor_ownership() -> void:
	for owner in [Node.new(), Node2D.new(), CharacterBody3D.new()]:
		var item := ParentAction.new()
		item.name = &"UseParent"
		item.effects = state({ &"done": true })
		var controller := GoapAgent.new()
		controller.actions = [item]
		controller.goals = [goal("UseParentGoal", { &"done": true })]
		owner.add_child(controller)
		root.add_child(owner)
		controller.set_physics_process(false)
		for frame in 300:
			controller._physics_process(0.1)
			if controller.world_state.get_state(&"done"):
				break
			await process_frame
		check(
			controller.actor == owner and owner.get_meta(&"planned", false),
			"actions execute on an ordinary %s parent" % owner.get_class()
		)
		check(
			controller.world_state.get_state(&"done"),
			"parent-independent execution applies successful effects"
		)
		owner.free()


func test_debugger_view() -> void:
	var item := action("Visible", {}, { &"prepared": true })
	item.result = GoapAction.Status.RUNNING
	var next := action("Finish", { &"prepared": true }, { &"done": true })
	next.result = GoapAction.Status.RUNNING
	var target := agent([item, next], [goal("VisibleGoal", { &"done": true })])
	target.request_replan()
	target._physics_process(0.1)
	var view: Control = load("res://addons/goap/debugger/goap_debugger.tscn").instantiate()
	root.add_child(view)
	view.add_agent(target)
	view.inspect(target)
	check(view.current_plan == target._current_plan, "runtime debugger can inspect existing plan")
	for frame in 4:
		await process_frame
	check(
		view.plan_browser.step_buttons[0].get_meta(
			"execution_status"
		) == "Running" and view.plan_browser.step_buttons[1].get_meta(
			"execution_status"
		) == "Pending",
		"live cards distinguish running and pending actions"
	)
	check(
		view.plan_browser.step_buttons.size() == 2 and view.plan_browser.step_buttons[
			1
		].position.y > view.plan_browser.step_buttons[0].position.y,
		"runtime actions follow vertical execution order"
	)
	view.plan_browser.inspect_step(0)
	check(
		view.plan_browser.inspector.get_children().any(
			func(row: Node) -> bool:
				return row.get_meta("fact", "") == &"prepared"),
		"runtime card includes individual effects"
	)
	var first_node: Button = view.plan_browser.step_buttons[0]
	view.follow_current.button_pressed = false
	view.plan_browser.step_scroll.scroll_vertical = 30
	var scroll: int = view.plan_browser.step_scroll.scroll_vertical
	target.world_state.set_state(&"external_fact", true)
	for frame in 2:
		await process_frame
	check(
		view.world_checks.has(&"external_fact") and view.world_checks.external_fact.button_pressed,
		"external world changes appear without completing an action"
	)
	item.result = GoapAction.Status.SUCCESS
	target._physics_process(0.1)
	for frame in 2:
		await process_frame
	check(
		view.plan_browser.step_buttons[
			0
		] == first_node and view.plan_browser.step_scroll.scroll_vertical == scroll,
		"step completion preserves nodes and manual viewport"
	)
	check(
		view.plan_browser.step_buttons[0].get_meta(
			"execution_status"
		) == "Completed" and view.plan_browser.step_buttons[1].get_meta(
			"execution_status"
		) == "Ready",
		"next action is not marked running before it starts"
	)
	view.plan_browser.inspect_step(1)
	check(
		view.plan_browser.inspector.get_children().any(
			func(row: Node) -> bool:
				return row.get_meta("fact", "") == &"prepared" and row.get_meta("satisfied", false)),
		"live preconditions reflect effects from completed actions"
	)
	target._physics_process(0.1)
	for frame in 2:
		await process_frame
	check(
		view.plan_browser.step_buttons[1].get_meta(
			"execution_status"
		) == "Running" and view.live_status.text.contains("Finish"),
		"live status follows the action starting on the next tick"
	)
	target._discard_plan()
	check(view.current_plan == null, "runtime debugger clears discarded plan")
	view.remove_agent(target)
	view.queue_free()
	await process_frame


func _initialize() -> void:
	run.call_deferred()
