extends "res://addons/goap/runtime/goap_performance_monitor.gd"
## Only the survival example's synthetic workload and progress estimates.
var stress_config: Dictionary = {}
var stress_agents: Array[GoapAgent] = []


func _ready() -> void:
	# The controller selects survival OR stress reports for these samples.
	auto_observe = false
	super._ready()


func extra_metrics_text() -> String:
	var text := ""
	var pending := pending_progress()
	if not stress_config.is_empty():
		text += "\nPending candidates %d · Expanded nodes %d\nOldest request %.1f s · Stress requests %d" % [
			pending.candidates,
			pending.expanded,
			pending.age_ms / 1000.0,
			pending.requests
		]
		var per_goal: int = preload("res://goap_example/stress_agent.gd").candidates_per_goal(
			stress_config.steps,
			stress_config.alternatives
		)
		text += "\nConfiguration %d goals × %d steps × %d alternatives\nTheoretical candidates per goal %d\nTheoretical candidates this round %d" % [
			stress_config.goals,
			stress_config.steps,
			stress_config.alternatives,
			per_goal,
			agent_count * int(stress_config.goals) * per_goal
		]
	return text


func pending_progress() -> Dictionary:
	var total := { "candidates": 0, "expanded": 0, "age_ms": 0.0, "requests": 0 }
	for agent in stress_agents:
		if not is_instance_valid(agent) or not agent.is_inside_tree():
			continue
		var progress: Dictionary = agent.live_progress()
		if progress.is_empty():
			continue
		total.requests += 1
		total.candidates += int(progress.get("candidates", 0))
		total.expanded += int(progress.get("expanded", 0))
		total.age_ms = maxf(total.age_ms, progress.get("age_ms", 0.0))
	return total


func metric_sections() -> Dictionary:
	return {
		"STRESS TEST": {
			"pending": "Pending candidates / nodes",
			"age": "Oldest request / active",
			"config": "Goals × steps × choices",
			"theory": "Candidates / goal / round"
		},
	}


func _update_metrics(_snapshot: Dictionary) -> void:
	var values := extra_metric_values()
	for key in values:
		metric_labels[key].text = values[key]
		metric_labels[key].tooltip_text = values[key]


func extra_metric_values() -> Dictionary:
	var values := {}
	var pending := pending_progress()
	var stress_metrics := $Body/Results/Metrics.get_node("STRESS TEST")
	stress_metrics.visible = not stress_config.is_empty()
	$Body/Results.visible = stress_metrics.visible
	$Body/Divider.visible = stress_metrics.visible
	if stress_metrics.visible:
		var per_goal: int = preload("res://goap_example/stress_agent.gd").candidates_per_goal(
			stress_config.steps,
			stress_config.alternatives
		)
		values.merge(
			{
				"pending": "%d / %d" % [pending.candidates, pending.expanded],
				"age": "%.1f s / %d" % [pending.age_ms / 1000.0, pending.requests],
				"config": "%d × %d × %d" % [
					stress_config.goals,
					stress_config.steps,
					stress_config.alternatives
				],
				"theory": "%d / %d" % [per_goal, agent_count * int(stress_config.goals) * per_goal],
			}
		)
	return values
