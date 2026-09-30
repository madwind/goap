extends Control

var world: Node3D
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(world):
		return
	var camera: Camera3D = world.camera
	for actor in world.actors:
		var point := camera.unproject_position(actor.global_position)
		var ability = actor._active_ability
		if ability != null and is_instance_valid(
			ability.target
		) and ability.target.is_inside_tree() and not ability.target.is_queued_for_deletion():
			draw_line(
				point,
				camera.unproject_position(ability.target.global_position),
				Color("69d8c2", 0.7),
				1.5,
				true
			)
