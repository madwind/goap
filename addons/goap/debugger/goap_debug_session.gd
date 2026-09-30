@tool
extends RefCounted
## Pure editor-side data. A session owns one observed Agent and bounded history.

signal changed
signal command_requested(message: String, data: Array)

const EVENT_LIMIT := 256
var connected := false
var agents: Array[Dictionary] = []
var selected_id := 0
var snapshot: Dictionary = {}
## Session-wide metrics, independent of the currently observed Agent.
var performance: Dictionary = {}
var events: Array[Dictionary] = []
var dropped := 0
var marker_enabled := false
var all_markers_enabled := false
var paused := false


func start() -> void:
	connected = true
	paused = false
	agents.clear()
	selected_id = 0
	snapshot.clear()
	performance.clear()
	events.clear()
	dropped = 0
	command_requested.emit("goap:list", [])
	command_requested.emit("goap:show_marker", [marker_enabled])
	command_requested.emit("goap:show_all_markers", [all_markers_enabled])
	changed.emit()


func stop() -> void:
	connected = false
	paused = false
	agents.clear()
	selected_id = 0
	snapshot.clear()
	performance.clear()
	events.clear()
	changed.emit()


func reset_performance() -> void:
	if connected:
		command_requested.emit("goap:reset_performance", [])


func set_paused(value: bool) -> void:
	if connected:
		command_requested.emit("goap:set_paused", [value])


func observe(id: int) -> void:
	if not connected:
		return
	_observe(id)
	changed.emit()


func set_marker_enabled(enabled: bool) -> void:
	marker_enabled = enabled
	if connected:
		command_requested.emit("goap:show_marker", [enabled])
	changed.emit()


func set_all_markers_enabled(enabled: bool) -> void:
	all_markers_enabled = enabled
	if connected:
		command_requested.emit("goap:show_all_markers", [enabled])
	changed.emit()


func _observe(id: int) -> void:
	if selected_id == id:
		return
	selected_id = id
	snapshot.clear()
	events.clear()
	dropped = 0
	command_requested.emit("goap:observe", [id])


func receive(message: String, payload: Dictionary) -> void:
	if not connected or int(payload.get("version", 0)) != 2:
		return
	match message:
		"goap:performance":
			if not payload.get("metrics") is Dictionary:
				return
			performance = payload.metrics.duplicate(true)
			paused = bool(payload.get("paused", false))
		"goap:agents":
			agents.clear()
			for item: Variant in payload.get("agents", []):
				if item is Dictionary and item.has("id") and item.has("path"):
					agents.append(item)
			if selected_id != 0 and not agents.any(func(item: Dictionary) -> bool: return int(item.id) == selected_id):
				selected_id = 0
				snapshot.clear()
				events.clear()
				dropped = 0
		"goap:plan":
			if selected_id == 0 or int(payload.get("agent_id", 0)) != selected_id:
				return
			var next_snapshot: Dictionary = payload.duplicate(true)
			var statistics: Dictionary = next_snapshot.get("statistics", {})
			if next_snapshot.has("decisions"):
				statistics.decisions = next_snapshot.decisions
				next_snapshot.erase("decisions")
			elif statistics.get("generation", -1) == snapshot.get("statistics", {}).get("generation", -2):
				var previous: Dictionary = snapshot.get("statistics", {})
				if previous.has("decisions"):
					statistics.decisions = previous.decisions
			next_snapshot.statistics = statistics
			snapshot = next_snapshot
		"goap:events":
			if selected_id == 0 or int(payload.get("agent_id", 0)) != selected_id:
				return
			dropped = int(payload.get("dropped", 0))
			for event: Dictionary in payload.get("events", []):
				events.append(event.duplicate(true))
				if events.size() > EVENT_LIMIT:
					events.pop_front()
		_:
			return
	changed.emit()
