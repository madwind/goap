@tool
class_name GoapVisionCone3D
extends GoapPerception

@export var distance: float = 0.0
@export var check_interval: float = 0.25
@export var fov_angle: float = 160.0
@export var perception_area: Area3D
@export var vision_cone_bone: Node3D
@export_flags_3d_physics var target_mask: int
var excitoi
var _timer: Timer
var _ray_cast: RayCast3D
var agent: GoapAgent:
	get:
		return get_parent()

func _ready() -> void:
	_ray_cast = RayCast3D.new()
	_ray_cast.enabled = false
	_ray_cast.collision_mask = target_mask
	vision_cone_bone.add_child(_ray_cast)
	_setup_timer()
	perception_area.body_exited.connect(target_lost.emit)


func _setup_timer() -> void:
	_timer = Timer.new()
	add_child(_timer)
	_timer.timeout.connect(_check_bodies)
	_timer.start(check_interval)


func _check_bodies() -> void:
	for body: Node3D in perception_area.get_overlapping_bodies():
		if not body == agent.actor and _is_body_visible(body):
			target_detected.emit(body)


func _is_body_visible(body: Node3D) -> bool:
	var targets := [body]
	var markers_node := body.get_node_or_null("GoapVisionCone3DMarkers") as GoapVisionCone3DMarkers
	if markers_node:
		targets += markers_node.markers
	for target: Node3D in targets:
		if _check_body(body, target):
			return true
	return false


func _check_body(body: Node3D, target: Node3D) -> bool:
	var direction_to_target := (target.global_position - vision_cone_bone.global_position).normalized()
	var ray_direction := vision_cone_bone.global_transform.basis.z.normalized()
	var center_to_target_angle := acos(direction_to_target.dot(ray_direction))
	var target_distance := target.global_position.distance_to(_ray_cast.global_position)
	if target_distance <= distance and center_to_target_angle <= deg_to_rad(fov_angle / 2):
		_ray_cast.look_at(target.global_position)
		_ray_cast.target_position = Vector3(0, 0, -target.global_position.distance_to(_ray_cast.global_position))
		_ray_cast.force_raycast_update()
		if _ray_cast.get_collider() == body:
			return true
	return false

func _get_configuration_warnings() -> PackedStringArray:
	var warnnings: Array[String] = []
	if !perception_area:
		warnnings.append("Parent node is null")
	if !vision_cone_bone:
		warnnings.append("Vision Cone Bone is null")
	return []
