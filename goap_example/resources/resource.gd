extends Node3D

const ItemDefinition = preload("res://goap_example/resources/item_definition.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")
@export var kind: StringName = &"tree"
@export var harvest_method: StringName
@export var drops: Array[ItemDefinition] = []
@export var item: ItemDefinition
var available := true
var in_transit := false
var stored_at_camp := false
var health := 3
var respawn_remaining := 0.0
@onready var visual: Node3D = $Visual
@onready var caption: Label3D = $Caption
var home := Vector3.ZERO
var time := 0.0


func _ready() -> void:
	health = max_health()
	if item != null:
		update_item_visual()
	home = position
	update_caption()


func update_item_visual() -> void:
	if item == null:
		return
	kind = item.kind
	var mesh := $Visual.get_child(0) as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.albedo_color = item.color
	material.roughness = 0.85
	mesh.material_override = material
	var bone := $Visual.get_node_or_null("Bone") as MeshInstance3D
	if kind == &"meat" or kind == &"cooked_meat":
		# The same pickup scene serves every item; meat gets its own clear shape.
		var flesh := SphereMesh.new()
		flesh.radius = 0.39
		flesh.height = 0.56
		mesh.mesh = flesh
		mesh.scale = Vector3(1.25, 1.0, 0.85)
		mesh.position = Vector3(-0.12, 0.4, 0)
		if bone == null:
			bone = MeshInstance3D.new()
			bone.name = "Bone"
			var bone_shape := CylinderMesh.new()
			bone_shape.top_radius = 0.075
			bone_shape.bottom_radius = 0.09
			bone_shape.height = 0.48
			bone.mesh = bone_shape
			bone.rotation.z = PI * 0.5
			bone.position = Vector3(0.43, 0.4, 0)
			var bone_material := StandardMaterial3D.new()
			bone_material.albedo_color = Color("ece2c8")
			bone_material.roughness = 0.9
			bone.material_override = bone_material
			$Visual.add_child(bone)
		bone.show()
	elif bone != null:
		bone.hide()


func _physics_process(delta: float) -> void:
	if in_transit:
		return
	time += delta
	if not available:
		respawn_remaining -= delta
		if respawn_remaining <= 0:
			if get_parent().has_method("relocate_resource"):
				get_parent().relocate_resource(self)
			available = true
			health = max_health()
			visual.visible = true
			var collision := get_node_or_null("Collider/CollisionShape3D") as CollisionShape3D
			if collision != null:
				collision.set_deferred("disabled", false)
	elif kind == &"animal":
		position = home + Vector3(sin(time * 0.45 + home.x), 0, cos(time * 0.35 + home.z)) * 0.65


## Capabilities are queries, not cached flags: availability is agent-relative.
## Games can override these methods for tools, species, permissions, etc.
func is_huntable(actor: Node3D) -> bool:
	return harvest_method == &"hunt" and _can_harvest(actor)


func is_choppable(actor: Node3D) -> bool:
	return harvest_method == &"chop" and _can_harvest(actor)


func can_harvest(actor: Node3D) -> bool:
	match harvest_method:
		&"hunt": return is_huntable(actor)
		&"chop": return is_choppable(actor)
	return not harvest_method.is_empty() and _can_harvest(actor)


func _can_harvest(_actor: Node3D) -> bool:
	return has_harvest_drops() and available


func has_harvest_drops() -> bool:
	return drops.any(func(drop: ItemDefinition) -> bool: return drop != null)


## Shared identity for provider observations and action preconditions.
func harvest_available_fact() -> StringName:
	var signatures := PackedStringArray()
	for drop in drops:
		if drop != null:
			signatures.append(drop.signature())
	return Facts.harvest_available(kind, harvest_method, signatures)


func update_caption() -> void:
	caption.visible = false
	caption.text = ""


func harvest_hit(damage := 1) -> bool:
	if not available or harvest_method.is_empty():
		return false
	health = maxi(0, health - maxi(1, damage))
	if health > 0:
		return false
	available = false
	visual.visible = false
	var collision := get_node_or_null("Collider/CollisionShape3D") as CollisionShape3D
	if collision != null:
		collision.set_deferred("disabled", true)
	update_caption()
	respawn_remaining = get_parent().resource_respawn_delay(kind)
	for drop in drops:
		if drop != null:
			var amount := randi_range(1, 3)
			if drop.kind == &"meat":
				amount = maxi(amount, 2)
			get_parent().drop_item(drop, global_position, amount)
	return true


func max_health() -> int:
	return 1 if kind == &"spring" else 3


## Equal profiles may share an action, but may never substitute different drops.
func harvest_profile() -> String:
	var signatures: Array[String] = []
	for drop in drops:
		if drop != null:
			signatures.append(drop.signature())
	signatures.sort()
	return "%s/%s:%s" % [String(kind).uri_encode(), String(harvest_method).uri_encode(), ",".join(signatures)]
