extends CharacterBody3D

const Map = preload("res://goap_example/survival/map.gd")
const Balance = preload("res://goap_example/survival/balance.gd")

var health := Balance.MONSTER_HEALTH
var attack_clock := 0.0
var target: Node3D
var _ground_steering: Dictionary = {}
@onready var caption: Label3D = $Caption


func _ready() -> void:
	caption.text = "MONSTER"
	set_meta(&"interaction_radius", Balance.MONSTER_ATTACK_RANGE)


func _physics_process(delta: float) -> void:
	if health <= 0:
		return
	var world := get_parent()
	var camp: Node3D = world.get_node("Campfire")
	var nearest: Node3D
	var best := INF
	for actor in world.actors:
		if actor.dead or actor.global_position.distance_to(camp.global_position) <= Balance.CAMP_SAFE_RADIUS:
			continue
		var distance := global_position.distance_squared_to(actor.global_position)
		if distance < best:
			best = distance
			nearest = actor
	target = nearest if best <= Balance.MONSTER_SIGHT_RADIUS * Balance.MONSTER_SIGHT_RADIUS else null
	attack_clock = maxf(0.0, attack_clock - delta)
	if target != null:
		var distance := global_position.distance_to(target.global_position)
		if distance <= Balance.MONSTER_ATTACK_RANGE:
			velocity = Vector3.ZERO
			if attack_clock <= 0.0:
				target.take_damage(Balance.MONSTER_DAMAGE)
				attack_clock = Balance.MONSTER_ATTACK_SECONDS
		else:
			var next_position := global_position.move_toward(target.global_position, Balance.MONSTER_SPEED * delta)
			if next_position.distance_to(camp.global_position) > Balance.CAMP_SAFE_RADIUS:
				_move_toward(next_position, delta)
	else:
		# Approach the camp immediately, even before an actor enters sight.
		var next_position := global_position.move_toward(camp.global_position, Balance.MONSTER_SPEED * delta)
		if next_position.distance_to(camp.global_position) > Balance.CAMP_SAFE_RADIUS:
			_move_toward(next_position, delta)
		else:
			velocity = Vector3.ZERO

func _move_toward(next_position: Vector3, _delta: float) -> void:
	Map.move_on_ground(self, next_position - global_position, Balance.MONSTER_SPEED, _ground_steering)
	global_position = Map.clamp_position(global_position)


func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(0, health - maxi(1, amount))
	if health == 0:
		get_parent().record_event("Monster defeated")
		get_parent().drop_meat(global_position, get_parent().actors.size())
		get_parent().monster_defeated(self)
		queue_free()
