extends Node3D
## Round timber fence around the camp; the four gaps are walk-through entrances.

const Map = preload("res://goap_example/survival/map.gd")
const RADIUS := Map.CAMP_FENCE_RADIUS
const GATE_HALF_WIDTH := Map.CAMP_GATE_HALF_WIDTH


func _ready() -> void:
	var timber := StandardMaterial3D.new()
	timber.albedo_color = Color("745239")
	timber.roughness = 0.95
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color("aa8050")
	cap.roughness = 0.9
	var gate_angle := asin(GATE_HALF_WIDTH / RADIUS)
	const SECTIONS_PER_ARC := 10
	for quadrant in 4:
		var start_angle := quadrant * PI * 0.5 + gate_angle
		var end_angle := (quadrant + 1) * PI * 0.5 - gate_angle
		for section in SECTIONS_PER_ARC:
			var a := lerpf(start_angle, end_angle, float(section) / SECTIONS_PER_ARC)
			var b := lerpf(start_angle, end_angle, float(section + 1) / SECTIONS_PER_ARC)
			_add_section(Vector3(cos(a), 0, sin(a)) * RADIUS, Vector3(cos(b), 0, sin(b)) * RADIUS, timber, cap, section == 0)
	_add_workbench(timber, cap)
	_add_meat_rack(timber)
	for entry in [
		["WoodStorage", Vector3(-3.9, 0, -4.1)],
		["StoneStorage", Vector3(1.8, 0, -4.1)],
		["WaterStorage", Vector3(-3.5, 0, 2.5)],
		["MeatStorage", Vector3(2.5, 0, 2.5)],
	]:
		var marker := Marker3D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		add_child(marker)


func _add_workbench(timber: Material, cap: Material) -> void:
	var bench := Node3D.new()
	bench.name = "Workbench"
	bench.position = Vector3(0, 0, -4.2)
	bench.set_meta(&"interaction_radius", 2.0)
	add_child(bench)
	_add_box(bench, Vector3(2.6, 0.22, 1.4), Vector3(0, 1.15, 0), cap)
	_add_box(bench, Vector3(2.3, 0.12, 0.95), Vector3(0, 0.4, 0), timber)
	for x in [-1.05, 1.05]:
		for z in [-0.48, 0.48]:
			_add_box(bench, Vector3(0.18, 1.1, 0.18), Vector3(x, 0.55, z), timber)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("89918c")
	stone.roughness = 0.9
	_add_box(bench, Vector3(0.85, 0.1, 0.12), Vector3(0.2, 1.32, 0), timber)
	_add_box(bench, Vector3(0.25, 0.2, 0.4), Vector3(0.5, 1.39, 0), stone)
	_add_box(bench, Vector3(0.55, 0.08, 0.4), Vector3(-0.65, 1.3, 0.1), stone)


func _add_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	parent.add_child(visual)


func _add_meat_rack(timber: Material) -> void:
	var rack := Node3D.new()
	rack.name = "MeatRack"
	rack.position = Vector3(3.5, 0, 2.85)
	add_child(rack)
	var tray := MeshInstance3D.new()
	var tray_mesh := BoxMesh.new()
	tray_mesh.size = Vector3(3.25, 0.24, 1.8)
	tray.mesh = tray_mesh
	tray.position.y = 0.16
	tray.material_override = timber
	rack.add_child(tray)
	for z in [-0.77, 0.77]:
		var rim := MeshInstance3D.new()
		var rim_mesh := BoxMesh.new()
		rim_mesh.size = Vector3(3.45, 0.22, 0.13)
		rim.mesh = rim_mesh
		rim.position = Vector3(0, 0.34, z)
		rim.material_override = timber
		rack.add_child(rim)


func _add_section(start: Vector3, finish: Vector3, timber: Material, cap: Material, first := true) -> void:
	if first:
		_add_post(start, timber, cap)
	_add_post(finish, timber, cap)
	var middle := (start + finish) * 0.5
	var length := start.distance_to(finish)
	for height in [0.42, 0.98]:
		var rail := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length, 0.15, 0.12)
		rail.mesh = mesh
		rail.material_override = timber
		rail.position = middle + Vector3.UP * height
		rail.rotation.y = -atan2(finish.z - start.z, finish.x - start.x)
		add_child(rail)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = middle + Vector3.UP * 0.68
	wall.rotation.y = -atan2(finish.z - start.z, finish.x - start.x)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length + 0.16, 1.36, 0.24)
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)


func _add_post(at: Vector3, timber: Material, cap: Material) -> void:
	var post := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.24, 1.42, 0.24)
	post.mesh = mesh
	post.material_override = timber
	post.position = at + Vector3.UP * 0.71
	add_child(post)
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(0.34, 0.12, 0.34)
	top.mesh = top_mesh
	top.material_override = cap
	top.position = at + Vector3.UP * 1.44
	add_child(top)
