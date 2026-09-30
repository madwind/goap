@tool
extends EditorDebuggerPlugin

signal session_added(id: int, model: RefCounted)

const Session = preload("res://addons/goap/debugger/goap_debug_session.gd")
const View = preload("res://addons/goap/debugger/goap_remote_view.gd")
var sessions: Dictionary = {}
var views: Dictionary = {}


func _has_capture(prefix: String) -> bool:
	return prefix == "goap"


func _setup_session(session_id: int) -> void:
	var model := Session.new()
	var session := get_session(session_id)
	sessions[session_id] = model
	model.command_requested.connect(func(message: String, data: Array) -> void:
		if session.is_active():
			session.send_message(message, data))
	session.started.connect(model.start)
	session.stopped.connect(model.stop)
	var view := View.new()
	view.name = "GOAP"
	views[session_id] = view
	session.add_session_tab(view)
	view.add_session(session_id, model)
	session_added.emit(session_id, model)
	if session.is_active():
		model.start()


func _capture(message: String, data: Array, session_id: int) -> bool:
	if message not in ["goap:agents", "goap:plan", "goap:events", "goap:performance"] or data.size() != 1 or not data[0] is Dictionary or not sessions.has(session_id):
		return false
	sessions[session_id].receive(message, data[0])
	return true
