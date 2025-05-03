extends GoapActor

var movement_speed: float = 2.0
var attack_range: float = 2.0
var weapon_pickup_range: float = 1.0
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D



func _ready() -> void:
	navigation_agent.velocity_computed.connect(_on_velocity_computed)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()


func pickup_item(target: Node3D) -> void:
	target.queue_free()

func kill_enemy(target: Node3D) -> void:
	target.queue_free()

func move_to(target_position: Vector3) -> void:
	navigation_agent.target_position = target_position
	var next_path_position := navigation_agent.get_next_path_position()
	look_at(next_path_position, Vector3.UP, true)
	velocity = global_position.direction_to(next_path_position) * movement_speed
	move_and_slide()
