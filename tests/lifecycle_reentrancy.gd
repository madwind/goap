extends SceneTree

var checks := 0
var failures := 0


class CallbackAction extends GoapAction:
	var at := ""
	var callback: Callable
	var stops := 0
	var performs := 0


	func is_valid(_agent: GoapAgent) -> bool:
		if at == "valid":
			callback.call()
		return true


	func start(_agent: GoapAgent) -> void:
		if at == "start":
			callback.call()


	func perform(_agent: GoapAgent, _delta: float) -> Status:
		performs += 1
		if at == "perform":
			callback.call()
		return Status.SUCCESS


	func stop(_agent: GoapAgent) -> void:
		stops += 1
		if at == "stop":
			callback.call()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LIFECYCLE: " + message)


func test_discard_during_callbacks(boundary: String) -> void:
	var agent := GoapAgent.new()
	agent.init_goap()
	var action := CallbackAction.new()
	action.effects.set_state(&"old_effect", true)
	var plan := GoapPlan.new()
	plan.actions = [action]
	agent._current_plan = plan
	var switch := func() -> void: agent._discard_plan()
	action.at = boundary
	action.callback = switch
	var successes := [0]
	plan.action_succeeded.connect(func(_is_last_step: bool) -> void: successes[0] += 1)
	if boundary == "state":
		agent.world_state.state_changed.connect(switch, CONNECT_ONE_SHOT)
	if boundary == "success":
		plan.action_succeeded.connect(
			func(_is_last_step: bool) -> void: switch.call(),
			CONNECT_ONE_SHOT
		)
	agent._follow_plan(0.016)
	check(agent._current_plan == null, boundary + ": old plan discarded")
	check(
		bool(agent.world_state.get_state(&"old_effect")) == (
			boundary in ["state", "success"]
		),
		boundary + ": effects commit only before post-commit callbacks"
	)
	check(
		successes[0] == (1 if boundary == "success" else 0),
		boundary + ": no stale success notification"
	)
	check(action.stops == (0 if boundary == "valid" else 1), boundary + ": cleanup runs once")
	if boundary in ["valid", "start"]:
		check(action.performs == 0, boundary + ": discarded plan prevents perform")
	action.callback = Callable()
	agent.free()


func test_cleanup_ownership() -> void:
	var agent := GoapAgent.new()
	agent.init_goap()
	var action := CallbackAction.new()
	var plan := GoapPlan.new()
	plan.actions = [action]
	agent._current_plan = plan
	var next := GoapAction.new()
	action.at = "stop"
	action.callback = func() -> void:
		agent._discard_plan()
		agent.current_action = next
	plan.execute(agent, 0.016)
	check(agent.current_action == next, "old cleanup cannot clear replacement action")
	action.callback = Callable()
	agent.free()


func test_recursive_execute() -> void:
	var agent := GoapAgent.new()
	agent.init_goap()
	var action := CallbackAction.new()
	var plan := GoapPlan.new()
	plan.actions = [action]
	agent._current_plan = plan
	action.at = "perform"
	action.callback = func() -> void: plan.execute(agent, 0.016)
	check(plan.execute(agent, 0.016) == GoapAction.Status.SUCCESS, "ordinary completion succeeds")
	check(
		action.performs == 1 and action.stops == 1 and plan.step == 1,
		"recursive execution cannot duplicate completion"
	)
	action.callback = Callable()
	agent.free()


func test_suspend_resume() -> void:
	var agent := GoapAgent.new()
	agent.init_goap()
	var action := CallbackAction.new()
	var plan := GoapPlan.new()
	plan.actions = [action]
	plan._started = true
	agent._current_plan = plan
	agent.current_action = action
	action.at = "stop"
	action.callback = func() -> void:
		agent.request_replan()
		agent.world_state.set_state(&"changed_during_stop", true)
	var pending := GoapPlanningRequest.new(agent)
	agent._budget_request = pending
	agent.suspend()
	check(
		agent.is_suspended and not agent.is_planning(),
		"suspend suppresses cleanup callback replanning"
	)
	check(pending.cancelled and not pending.is_current(), "suspend invalidates pending computation")
	check(
		agent.current_plan == null and agent.current_action == null and action.stops == 1,
		"suspend releases execution exactly once"
	)
	agent.suspend()
	check(action.stops == 1, "repeated suspend is idempotent")
	agent.resume()
	var generation := agent.planning_generation
	agent.resume()
	check(
		not agent.is_suspended and agent.is_planning() and agent.planning_generation == generation,
		"resume requests one fresh generation"
	)
	action.callback = Callable()
	agent.free()


func test_cancel_planning_keeps_execution() -> void:
	var agent := GoapAgent.new()
	agent.init_goap()
	var action := CallbackAction.new()
	var plan := GoapPlan.new()
	plan.actions = [action]
	plan._started = true
	agent._current_plan = plan
	agent.current_action = action
	agent.request_replan()
	var pending := GoapPlanningRequest.new(agent)
	agent._budget_request = pending
	agent.cancel_planning()
	check(
		not agent.is_planning() and pending.cancelled and not pending.is_current(),
		"cancel_planning invalidates computation"
	)
	check(
		agent.current_plan == plan and agent.current_action == action and action.stops == 0,
		"cancel_planning preserves active execution"
	)
	agent.suspend()
	agent.free()


func _initialize() -> void:
	for boundary in ["valid", "start", "perform", "stop", "state", "success"]:
		test_discard_during_callbacks(boundary)
	test_cleanup_ownership()
	test_recursive_execute()
	test_suspend_resume()
	test_cancel_planning_keeps_execution()
	print("GOAP lifecycle reentrancy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
