extends PanelContainer
## Compact selection marker that follows the selected agent's head.

var world: Node3D
@onready var agent_label: Label = $Column/Agent


func _process(_delta: float) -> void:
	if not is_instance_valid(world) or world.actors.is_empty():
		visible = false
		return
	var actor: Node3D = world.actors[world.selected_index]
	var head: Vector3 = actor.global_position + Vector3.UP * 2.2
	var camera: Camera3D = world.camera
	if camera.is_position_behind(head):
		visible = false
		return
	agent_label.text = "Agent #%d" % (world.selected_index + 1)
	var screen_position: Vector2 = camera.unproject_position(head)
	var map_width: float = world.hud.map_width()
	position = Vector2(
		clampf(screen_position.x - size.x * 0.5, 4.0, maxf(4.0, map_width - size.x - 4.0)),
		screen_position.y - size.y - 6.0
	)
	visible = true
