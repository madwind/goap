class_name GoapPerformanceMonitor
extends VBoxContainer
## Real clock samples, independent of simulation speed. Runs after the scheduler.
@export var auto_observe := true

var samples := GoapPerformanceStatistics.new()
var scheduler: GoapPlanningScheduler
var frame_count: int:
	get: return samples.frame_count
var schedule_total: float:
	get: return samples.schedule_total
var schedule_peak: float:
	get: return samples.schedule_peak
var planning_count: int:
	get: return samples.planning_count
var idle_count: int:
	get: return samples.idle_count
var planning_total: float:
	get: return samples.planning_total
var planning_peak: float:
	get: return samples.planning_peak
var latency_total: float:
	get: return samples.latency_total
var latency_peak: float:
	get: return samples.latency_peak
var preparation_total: float:
	get: return samples.preparation_total
var search_total: float:
	get: return samples.search_total
var evaluation_total: float:
	get: return samples.evaluation_total
var next_update := 0
var next_log := 0
var agent_count := 0
var candidate_total: int:
	get: return samples.candidate_total
var searched_goals: int:
	get: return samples.searched_goals
var incomplete_requests: int:
	get: return samples.incomplete_requests
var metric_labels: Dictionary = {}
var _agents: Array[GoapAgent] = []
var _initialized := false


func _enter_tree() -> void:
	# Moving a page between windows re-enters the tree without another _ready().
	if _initialized:
		_start_observing()


func _ready() -> void:
	process_priority = 1000
	scheduler = GoapPlanningScheduler.for_tree(get_tree())
	_build_metrics()
	reset_samples()
	_initialized = true
	_start_observing()


func _start_observing() -> void:
	if auto_observe:
		if not get_tree().node_added.is_connected(_observe_node):
			get_tree().node_added.connect(_observe_node)
			get_tree().node_removed.connect(_forget_node)
		_scan_agents(get_tree().root)


func _process(_delta: float) -> void:
	var snapshot := scheduler.statistics
	if snapshot.is_empty():
		return
	samples.record_frame(snapshot)
	var now := Time.get_ticks_msec()
	if now >= next_update:
		next_update = now + 200
		_update_metrics(snapshot)
	if now >= next_log:
		next_log = now + 2000
		if $Body/Settings/Console.button_pressed:
			print(
				"[GOAP performance] Agents=%d | %s" % [
					agent_count,
					metrics_text(snapshot).replace("\n", " | ")
				]
			)


func reset_samples() -> void:
	samples.reset()
	next_update = 0
	next_log = Time.get_ticks_msec() + 2000


func record_planning(report: Dictionary) -> void:
	samples.record_planning(report)


func metrics_text(snapshot: Dictionary) -> String:
	var count := maxi(1, planning_count)
	var pending := pending_progress()
	var text := "FPS %d  ·  Agents %d\nQueued %d  /  Worker tasks %d\nScheduler frame %.3f ms  /  Budget %.2f ms\nScheduler average %.3f ms  /  Peak %.3f ms\nFrame budget overrun %.3f ms\nPlans completed %d  ·  No planning needed %d" % [
		Engine.get_frames_per_second(),
		agent_count,
		snapshot.get("queued_agents", 0),
		snapshot.get("active_workers", 0),
		snapshot.get("frame_time_ms", 0.0),
		scheduler.frame_budget_ms,
		schedule_total / maxi(1, frame_count),
		schedule_peak,
		snapshot.get("overrun_ms", 0.0),
		planning_count,
		idle_count
	]
	text += "\nActual candidates %d · Goals searched %d\nIncomplete searches %d (including node limits)" % [
		candidate_total + int(pending.candidates),
		searched_goals,
		incomplete_requests
	]
	text += extra_metrics_text()
	if planning_count == 0:
		return text + "\nPlanning compute / response: waiting for completed samples"
	return text + "\nPlanning compute average %.3f / peak %.3f ms\n  Prepare %.3f · Search %.3f · Evaluate %.3f ms\nPlanning response average %.2f / peak %.2f ms" % [
		planning_total / count,
		planning_peak,
		preparation_total / count,
		search_total / count,
		evaluation_total / count,
		latency_total / count,
		latency_peak
	]


func pending_progress() -> Dictionary:
	return { "candidates": 0, "expanded": 0, "age_ms": 0.0, "requests": 0 }


func extra_metrics_text() -> String:
	return ""


func metric_sections() -> Dictionary:
	return GoapPerformanceStatistics.sections()


func _build_metrics() -> void:
	var sections := metric_sections()
	for title in sections:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 7)
		$Body/Results/Metrics.add_child(section)
		section.name = title
		var heading := Label.new()
		heading.text = title
		heading.add_theme_font_size_override("font_size", 13)
		heading.add_theme_color_override("font_color", Color("9eb5cc"))
		section.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 6)
		section.add_child(grid)
		for key in sections[title]:
			var caption := Label.new()
			caption.text = sections[title][key]
			caption.add_theme_font_size_override("font_size", 14)
			caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(caption)
			var value := Label.new()
			value.text = "—"
			value.custom_minimum_size.x = 140
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			value.clip_text = true
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value.add_theme_font_size_override("font_size", 14)
			grid.add_child(value)
			metric_labels[key] = value


func _update_metrics(snapshot: Dictionary) -> void:
	var metrics := samples.snapshot(snapshot, scheduler.frame_budget_ms, agent_count)
	metrics.candidates += int(pending_progress().candidates)
	var values := GoapPerformanceStatistics.display_values(metrics)
	values.merge(extra_metric_values())
	for key in values:
		metric_labels[key].text = values[key]
		metric_labels[key].tooltip_text = values[key]
	metric_labels.overrun.add_theme_color_override(
		"font_color",
		Color("e3ad5c") if float(snapshot.get("overrun_ms", 0.0)) > 0.0 else Color("e6f0fa")
	)


func extra_metric_values() -> Dictionary:
	return {}


func _scan_agents(node: Node) -> void:
	_observe_node(node)
	for child in node.get_children():
		_scan_agents(child)


func _observe_node(node: Node) -> void:
	if node is GoapAgent and not _agents.has(node):
		_agents.append(node)
		node.planning_measured.connect(record_planning)
		agent_count = _agents.size()


func _forget_node(node: Node) -> void:
	if node is GoapAgent and _agents.has(node):
		_agents.erase(node)
		if node.planning_measured.is_connected(record_planning):
			node.planning_measured.disconnect(record_planning)
		agent_count = _agents.size()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_observe_node):
		get_tree().node_added.disconnect(_observe_node)
		get_tree().node_removed.disconnect(_forget_node)
	for agent in _agents.duplicate():
		_forget_node(agent)
