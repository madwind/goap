@tool
class_name GoapPerformanceStatistics
extends RefCounted
## Bounded numeric aggregates, independent of any game, window or editor UI.

var frame_count := 0
var schedule_total := 0.0
var schedule_peak := 0.0
var planning_count := 0
var idle_count := 0
var planning_total := 0.0
var planning_peak := 0.0
var latency_total := 0.0
var latency_peak := 0.0
var preparation_total := 0.0
var search_total := 0.0
var evaluation_total := 0.0
var candidate_total := 0
var searched_goals := 0
var incomplete_requests := 0
var epoch := 0
var _started_msec := Time.get_ticks_msec()


func reset() -> void:
	frame_count = 0
	schedule_total = 0.0
	schedule_peak = 0.0
	planning_count = 0
	idle_count = 0
	planning_total = 0.0
	planning_peak = 0.0
	latency_total = 0.0
	latency_peak = 0.0
	preparation_total = 0.0
	search_total = 0.0
	evaluation_total = 0.0
	candidate_total = 0
	searched_goals = 0
	incomplete_requests = 0
	_started_msec = Time.get_ticks_msec()
	epoch += 1


func record_frame(scheduler_statistics: Dictionary) -> void:
	if scheduler_statistics.is_empty():
		return
	var duration := float(scheduler_statistics.get("frame_time_ms", 0.0))
	frame_count += 1
	schedule_total += duration
	schedule_peak = maxf(schedule_peak, duration)


func record_planning(report: Dictionary) -> void:
	# Explicitly pending reports are never samples. Callers may also provide a
	# completed numeric summary without the scheduler's request_finished field.
	if not report.get("request_finished", true) or report.get("reason") == "pending":
		return
	if report.get("reason") == "no_goal":
		idle_count += 1
		return
	var request: Dictionary = report.get("request", {})
	candidate_total += int(request.get("candidate_count", 0))
	searched_goals += int(request.get("searched_goals", 0))
	if not report.get("search_complete", false):
		incomplete_requests += 1
	var compute := float(request.get("planning_time_ms", 0.0))
	var latency := float(request.get("latency_ms", 0.0))
	planning_count += 1
	planning_total += compute
	planning_peak = maxf(planning_peak, compute)
	latency_total += latency
	latency_peak = maxf(latency_peak, latency)
	preparation_total += float(request.get("preparation_time_ms", 0.0))
	search_total += float(request.get("search_time_ms", 0.0))
	evaluation_total += float(request.get("evaluation_time_ms", 0.0))


## A fresh, fixed-size snapshot. It contains no Agent, Action or worker data.
func snapshot(scheduler_statistics: Dictionary, budget_ms: float, agent_count: int) -> Dictionary:
	var count := maxi(1, planning_count)
	return {
		"epoch": epoch,
		"elapsed_sec": (Time.get_ticks_msec() - _started_msec) / 1000.0,
		"agent_count": agent_count,
		"fps": int(Engine.get_frames_per_second()),
		"queued": int(scheduler_statistics.get("queued_agents", 0)),
		"workers": int(scheduler_statistics.get("active_workers", 0)),
		"frame_ms": float(scheduler_statistics.get("frame_time_ms", 0.0)),
		"budget_ms": budget_ms,
		"overrun_ms": float(scheduler_statistics.get("overrun_ms", 0.0)),
		"frames": frame_count,
		"schedule_avg_ms": schedule_total / maxi(1, frame_count),
		"schedule_peak_ms": schedule_peak,
		"samples": planning_count,
		"idle": idle_count,
		"compute_avg_ms": planning_total / count,
		"compute_peak_ms": planning_peak,
		"prepare_avg_ms": preparation_total / count,
		"search_avg_ms": search_total / count,
		"evaluate_avg_ms": evaluation_total / count,
		"response_avg_ms": latency_total / count,
		"response_peak_ms": latency_peak,
		"candidates": candidate_total,
		"goals": searched_goals,
		"incomplete": incomplete_requests,
	}


static func sections() -> Dictionary:
	return {
		"SCHEDULER": {
			"agents": "Agents",
			"fps": "Frames / second",
			"queue": "Queued / worker tasks",
			"frame": "Frame / budget",
			"schedule": "Average / peak",
			"overrun": "Budget overrun",
		},
		"PLANNING": {
			"completed": "Completed / idle checks",
			"compute": "Compute · average / peak",
			"stages": "Prepare / search / evaluate",
			"latency": "Response · average / peak",
		},
		"SEARCH": { "candidates": "Actual candidates", "goals": "Goals searched / incomplete" },
	}


static func display_values(metrics: Dictionary) -> Dictionary:
	if metrics.is_empty():
		var empty := {}
		for section: Dictionary in sections().values():
			for key in section:
				empty[key] = "—"
		return empty
	var completed := int(metrics.get("samples", 0))
	return {
		"agents": str(metrics.get("agent_count", 0)),
		"fps": str(metrics.get("fps", 0)),
		"queue": "%d / %d" % [metrics.get("queued", 0), metrics.get("workers", 0)],
		"frame": "%.3f / %.2f ms" % [metrics.get("frame_ms", 0.0), metrics.get("budget_ms", 0.0)],
		"schedule": "%.3f / %.3f ms" % [metrics.get("schedule_avg_ms", 0.0), metrics.get("schedule_peak_ms", 0.0)],
		"overrun": "%.3f ms" % metrics.get("overrun_ms", 0.0),
		"completed": "%d / %d" % [completed, metrics.get("idle", 0)],
		"compute": "%.3f / %.3f ms" % [metrics.get("compute_avg_ms", 0.0), metrics.get("compute_peak_ms", 0.0)] if completed else "Waiting for samples",
		"stages": "%.3f / %.3f / %.3f ms" % [metrics.get("prepare_avg_ms", 0.0), metrics.get("search_avg_ms", 0.0), metrics.get("evaluate_avg_ms", 0.0)] if completed else "—",
		"latency": "%.2f / %.2f ms" % [metrics.get("response_avg_ms", 0.0), metrics.get("response_peak_ms", 0.0)] if completed else "—",
		"candidates": str(metrics.get("candidates", 0)),
		"goals": "%d / %d" % [metrics.get("goals", 0), metrics.get("incomplete", 0)],
	}
