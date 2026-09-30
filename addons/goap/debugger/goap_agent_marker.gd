extends CanvasLayer
## Optional visual identification only. Never reads or consumes game input.

var agent: GoapAgent
var caption := ""
var overlay: Control
var highlighted := true
var stack_index := 0


class MarkerCanvas extends Control:
	var marker: CanvasLayer


	func _draw() -> void:
		var placement: Dictionary = marker.placement()
		if placement.is_empty():
			return
		var point: Vector2 = placement.point
		var color := Color("70e1ff") if marker.highlighted else Color("ffd080")
		var font := ThemeDB.fallback_font
		var font_size := 18
		# Compact numbers keep a crowd readable; the observed Agent keeps its name.
		var text: String = marker.caption if marker.highlighted else marker.caption.get_slice(" · ", 0)
		var width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 20, size.x - 12)
		var box := Rect2(Vector2(clampf(point.x - width * 0.5, 6, maxf(6, size.x - width - 6)), maxf(6, point.y - 64 - marker.stack_index * 34)), Vector2(width, 30))
		draw_arc(point, 17, 0, TAU, 40, Color(0, 0, 0, 0.8), 5, true)
		draw_arc(point, 17, 0, TAU, 40, color, 2, true)
		draw_line(point + Vector2(0, -18), Vector2(box.get_center().x, box.end.y), color, 2, true)
		draw_rect(box, Color("102b39"))
		draw_rect(box, color, false, 1)
		draw_string(font, box.position + Vector2(10, 21), text, HORIZONTAL_ALIGNMENT_LEFT, width - 20, font_size, color)


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = MarkerCanvas.new()
	overlay.marker = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.focus_mode = Control.FOCUS_NONE
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func spatial_owner(value: GoapAgent) -> Node:
	if not is_instance_valid(value):
		return null
	var current := value.get_parent()
	while current != null and not current is Viewport:
		if current is Node3D or current is CanvasItem:
			return current
		current = current.get_parent()
	return null


func track(value: GoapAgent, title: String) -> void:
	agent = value
	caption = title
	if is_instance_valid(agent) and agent.is_inside_tree():
		custom_viewport = agent.get_viewport()
	else:
		custom_viewport = get_viewport()
	if overlay != null:
		overlay.queue_redraw()


## Screen-space marker; deliberately does not raycast, move cameras or infer selection.
func placement() -> Dictionary:
	if not is_instance_valid(agent) or not agent.is_inside_tree() or agent.is_queued_for_deletion():
		return {}
	var actor := spatial_owner(agent)
	if actor == null or actor.is_queued_for_deletion() or not actor.is_visible_in_tree():
		return {}
	var viewport := actor.get_viewport()
	var point: Vector2
	if actor is Node3D:
		var camera := viewport.get_camera_3d()
		if camera == null or camera.is_position_behind(actor.global_position):
			return {}
		point = camera.unproject_position(actor.global_position)
	else:
		var local_point: Vector2 = actor.size * 0.5 if actor is Control else Vector2.ZERO
		point = actor.get_global_transform_with_canvas() * local_point
	if not viewport.get_visible_rect().has_point(point):
		return {}
	return { "point": point }


func _process(_delta: float) -> void:
	if is_instance_valid(agent) and agent.is_inside_tree() and custom_viewport != agent.get_viewport():
		custom_viewport = agent.get_viewport()
	overlay.queue_redraw()
