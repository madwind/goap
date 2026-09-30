extends Node

var checks := 0
var failures := 0


func _ready() -> void:
	var binary := "--binary" in OS.get_cmdline_user_args()
	if "--standalone" in OS.get_cmdline_user_args():
		check(
			OS.has_feature("template") and not OS.has_feature("editor"),
			"running in standalone release template"
		)
	check(
		get_script().source_code.is_empty() == binary,
		"ordinary scripts follow preset export mode"
	)
	var model := load("res://tests/export_fixture/costs/derived.gd") as GDScript
	check(not model.source_code.is_empty(), "custom cost model source is preserved")
	check(
		not model.get_base_script().source_code.is_empty(),
		"model inheritance source is preserved"
	)
	check(
		GoapPlanningSafety.inspect_model(model).is_empty(),
		"inherited safe model passes runtime audit"
	)
	var unsafe_model := load("res://tests/export_fixture/costs/unsafe.gd") as GDScript
	check(
		not GoapPlanningSafety.inspect_model(unsafe_model).is_empty(),
		"unsafe model still rejected in exported pack"
	)
	var agent := GoapAgent.new()
	agent.goap_script_folder = "res://tests/export_fixture"
	add_child(agent)
	agent.set_physics_process(false)
	check(
		agent.actions.size() == 1 and agent.goals.size() == 1
		and agent.world_state.size() == 0,
		"exported action and goal discovery starts without authored state"
	)
	var scheduler := GoapPlanningScheduler.for_tree(get_tree())
	scheduler.enqueue(agent)
	var started := Time.get_ticks_msec()
	while agent.is_planning() and Time.get_ticks_msec() - started < 10000:
		await get_tree().process_frame
	check(
		agent._current_plan != null and agent._current_plan.cost == 7.0,
		"exported worker planning uses custom inherited model"
	)
	check(
		agent.planning_statistics.get("evaluation_on_worker", false),
		"exported model evaluated on worker"
	)
	agent._follow_plan(0.016)
	check(
		agent.world_state.get_state(&"done"),
		"exported action executes and commits effects"
	)
	agent.queue_free()
	await get_tree().process_frame
	print("GOAP export smoke: %d checks, %d failures" % [checks, failures])
	# Release templates may suppress stdout; persist an explicit completion report.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var file := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			if file == null:
				get_tree().quit(1)
				return
			file.store_string(
				JSON.stringify(
					{
						"checks": checks,
						"failures": failures,
						"template": OS.has_feature("template"),
						"completed": true
					}
				)
			)
			file.close()
	get_tree().quit(1 if failures else 0)


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EXPORT: " + message)

