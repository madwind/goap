extends Node3D

const MeatScene = preload("res://goap_example/resources/meat.tscn")
const ResourceObject = preload("res://goap_example/resources/resource.gd")
const Balance = preload("res://goap_example/survival/balance.gd")
const Camp = preload("res://goap_example/camp.gd")
const AgentScene = preload("res://goap_example/agent/agent.tscn")
const TreeScene = preload("res://goap_example/resources/tree.tscn")
const AnimalScene = preload("res://goap_example/resources/animal.tscn")
const SpringScene = preload("res://goap_example/resources/spring.tscn")
const StoneScene = preload("res://goap_example/resources/stone.tscn")
const MonsterScene = preload("res://goap_example/monster/monster.tscn")
const StressController = preload("res://goap_example/stress_controller.gd")
const Map = preload("res://goap_example/survival/map.gd")
@export var random_resources := true
@export var resource_seed := 0
var resource_rng := RandomNumberGenerator.new()
var stress := StressController.new()
@onready var hud = $HUD
@export_range(1, 512) var agent_count := 6
var actors: Array[Node3D] = []
var monsters: Array[Node3D] = []
var monster_spawn_clock := 0.0
var monster_serial := 0
var alert_monster: Node3D
var selected_index := 0
var extra_resources: Array[Node3D] = []
var resources: Array[Node3D] = []
var resource_serial := 0
const CAMP_STOCK_LIMIT := Camp.STOCK_LIMIT
@onready var camera: Camera3D = $Environment/Camera3D

# World-facing convenience API for the HUD and fixture scripts.
# Campfire owns the actual timer and inventory.
var fire_remaining: float:
	get: return $Campfire.fire_remaining
	set(value): $Campfire.fire_remaining = value
var events: Array[String] = []
var elapsed := 0.0
var hud_clock := 0.0
@onready var overlay: Control = $HUD/Root/Overlay


func _ready() -> void:
	var inspector := get_node_or_null("/root/GoapInspector")
	if inspector != null:
		inspector.set_auto_show_monitor(false)
	if resource_seed == 0:
		resource_rng.randomize()
	else:
		resource_rng.seed = resource_seed
	_fit_map_to_screen()
	monster_spawn_clock = resource_rng.randf_range(Balance.FIRST_MONSTER_SECONDS.x, Balance.FIRST_MONSTER_SECONDS.y)
	get_viewport().size_changed.connect(_fit_map_to_screen)
	overlay.world = self
	# Sensing iterates resources only, rather than scanning hundreds of agents.
	for child in get_children():
		_track_resource(child)
	for resource in resources:
		relocate_resource(resource)
	child_entered_tree.connect(_track_resource)
	child_exiting_tree.connect(_untrack_resource)
	stress.initialize(get_tree(), hud.performance)
	hud.bind_world(self)
	actors.append($Agent)
	$Agent/GoapAgent.planning_measured.connect(stress.record_survival_planning)
	agent_count = int(get_tree().get_meta(&"example_agent_count", agent_count))
	set_agent_count(agent_count)
	record_event("Agents are exploring the world")
	hud.update_world(self)


func _physics_process(delta: float) -> void:
	elapsed += delta
	_update_monster_alert()
	# Combat cannot consume the following recovery interval or build a backlog.
	if monsters.is_empty():
		monster_spawn_clock = maxf(0.0, monster_spawn_clock - delta)
		if monster_spawn_clock <= 0.0 and _population_ready_for_monster():
			spawn_monster()
	hud_clock += delta
	if hud_clock >= 0.1:
		hud_clock = 0
		hud.update_world(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var nearest_index := -1
		var distance := 24.0
		for index in actors.size():
			var candidate := camera.unproject_position(actors[index].global_position).distance_to(event.position)
			if candidate < distance:
				nearest_index = index
				distance = candidate
		if nearest_index >= 0:
			select_agent(nearest_index + 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	match event.physical_keycode:
		KEY_H: make_hungry()
		KEY_J: make_starving()
		KEY_K: make_thirsty()
		KEY_T: toggle_speed()
		KEY_R: reset_demo()
		KEY_F11: toggle_fullscreen()


func set_agent_count(count: int) -> void:
	agent_count = clampi(count, 1, 512)
	get_tree().set_meta(&"example_agent_count", agent_count)
	while actors.size() > agent_count:
		var actor := actors.pop_back() as Node3D
		actor.drop_carried_item()
		remove_child(actor)
		actor.queue_free()
	while actors.size() < agent_count:
		var actor := AgentScene.instantiate() as Node3D
		var index := actors.size()
		actor.name = "Agent%03d" % (index + 1)
		# A deterministic low-discrepancy layout fills the expanded map.
		actor.position = Vector3(
			fposmod(index * 0.61803398875, 1.0) * 72.0 - 36.0,
			0,
			fposmod(index * 0.754877666, 1.0) * 48.0 - 24.0
		)
		actor.position = Map.clamp_position(actor.position)
		actor.get_node("GoapAgent").planning_measured.connect(stress.record_survival_planning)
		actors.append(actor)
		add_child(actor)
	# Keep bounded planning comparisons for the small interactive population.
	for index in mini(actors.size(), 12):
		var goap_agent: GoapAgent = actors[index].get_node("GoapAgent")
		if not goap_agent.diagnostics_enabled:
			goap_agent.begin_diagnostics()
	_sync_source_resources()
	hud.set_population(agent_count)
	select_agent(mini(selected_index + 1, agent_count))
	stress.configure_population(actors)
	record_event("Population set to %d agents; performance samples reset" % agent_count)


func select_agent(value: float) -> void:
	selected_index = clampi(int(value) - 1, 0, actors.size() - 1)
	hud.select_agent(selected_index)
	for index in actors.size():
		actors[index].selected = index == selected_index
		actors[index].get_node("AlertRing").visible = index == selected_index and not actors[
			index
		].dead
	hud.update_world(self)


func replan_all() -> void:
	if stress.restart_round(actors):
		record_event("Started a new planning stress test round")
		return
	for actor in actors:
		actor.get_node("GoapAgent").request_replan()
	record_event("Requested replanning for all %d agents" % actors.size())


func resource_respawn_delay(kind: StringName) -> float:
	var interval: Vector2 = Balance.TREE_RESPAWN_SECONDS
	match kind:
		&"spring": interval = Balance.SPRING_RESPAWN_SECONDS
		&"stone": interval = Balance.STONE_RESPAWN_SECONDS
		&"animal": interval = Balance.ANIMAL_RESPAWN_SECONDS
	# Keep the fixed teaching fixture deterministic in both placement and timing.
	if not random_resources:
		return (interval.x + interval.y) * 0.5
	return resource_rng.randf_range(interval.x, interval.y)


func relocate_resource(resource: Node3D) -> void:
	if resource.kind == &"meat":
		return
	# Leave room for dropped items and for animals wandering around their home.
	var clearance: float = Balance.CAMP_RESOURCE_CLEARANCE + (2.0 if resource.kind == &"animal" else 1.0)
	if not random_resources:
		var from_camp: Vector3 = resource.position - $Campfire.position
		from_camp.y = 0.0
		if from_camp.length() < clearance:
			if from_camp.is_zero_approx():
				from_camp = Vector3.RIGHT
			resource.position = $Campfire.position + from_camp.normalized() * clearance
		resource.home = resource.position
		return
	var bounds := Map.half_size - Vector2(1.5, 1.5)
	var spot := Vector3.ZERO
	var attempts := 1 if resources.size() > 96 else 64
	for attempt in attempts:
		spot = Vector3(
			resource_rng.randf_range(-bounds.x, bounds.x),
			0,
			resource_rng.randf_range(-bounds.y, bounds.y)
		)
		var clear := spot.distance_to($Campfire.position) >= clearance
		if attempts > 1:
			for other in resources:
				if other != resource and other.available and spot.distance_to(other.position) < 2.8:
					clear = false
		if clear:
			break
	# The large-population fast path may skip spacing, but still keeps the
	# camp center free of resources.
	var from_camp: Vector3 = spot - $Campfire.position
	if from_camp.length() < clearance:
		if from_camp.is_zero_approx():
			from_camp = Vector3.RIGHT
		spot = $Campfire.position + from_camp.normalized() * clearance
	resource.position = spot
	resource.home = spot


func drop_meat(at: Vector3, count := 1) -> void:
	drop_item(preload("res://goap_example/resources/raw_meat.tres"), at, count)


func drop_item(item: Resource, at: Vector3, count := 1) -> void:
	if count <= 0:
		return
	var columns := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / columns)
	for index in count:
		var column := index % columns
		var row := index / columns
		var offset := Vector3(column - (columns - 1) * 0.5, 0, row - (rows - 1) * 0.5) * 1.3
		var ground_item := MeatScene.instantiate()
		ground_item.item = item
		ground_item.kind = item.kind
		ground_item.position = Map.clamp_position(to_local(at + offset))
		add_child(ground_item)


func nearest(kind: StringName, from: Vector3) -> Node3D:
	var found: Node3D
	var distance := INF
	for child in resources:
		if child.kind == kind and child.available and not child.in_transit and not child.is_queued_for_deletion():
			var candidate: float = from.distance_squared_to(child.global_position)
			if candidate < distance:
				found = child
				distance = candidate
	return found


func camp_stock_count(kind: StringName) -> int:
	return $Campfire.stock_count(kind)


func has_crafting_materials() -> bool:
	return $Campfire.has_crafting_materials()


func stockpile_full() -> bool:
	return $Campfire.stockpile_full()


func unstore_item(item: Node3D) -> void:
	$Campfire.remove_item(item)


func store_cargo(item: Node3D) -> void:
	$Campfire.store_item(item)


func toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN
	)


func nearest_monster(from: Vector3, radius: float) -> Node3D:
	var found: Node3D
	var best := radius * radius
	for monster in monsters:
		if not is_instance_valid(monster) or monster.is_queued_for_deletion() or monster.health <= 0:
			continue
		var distance := from.distance_squared_to(monster.global_position)
		if distance < best:
			best = distance
			found = monster
	return found


func shared_monster_alert() -> Node3D:
	return alert_monster if is_instance_valid(alert_monster) and not alert_monster.is_queued_for_deletion() and alert_monster.health > 0 else null


func _update_monster_alert() -> void:
	if shared_monster_alert() == null:
		alert_monster = null
		for actor in actors:
			if actor.dead:
				continue
			var spotted := nearest_monster(actor.global_position, actor.ALERT_RADIUS)
			if spotted != null:
				alert_monster = spotted
				record_event("%s spotted %s; all agents alerted" % [actor.name, spotted.name])
				break


func spawn_monster() -> Node3D:
	if monsters.size() >= Balance.MAX_MONSTERS:
		return null
	var bounds := Map.half_size - Vector2(2, 2)
	var spot := Vector3.ZERO
	var clear := false
	for attempt in 64:
		spot = Vector3(resource_rng.randf_range(-bounds.x, bounds.x), 0, resource_rng.randf_range(-bounds.y, bounds.y))
		# Arrive from a map edge so spawning itself never inflicts unavoidable damage.
		if resource_rng.randf() < 0.5:
			spot.x = bounds.x if resource_rng.randf() < 0.5 else -bounds.x
		else:
			spot.z = bounds.y if resource_rng.randf() < 0.5 else -bounds.y
		clear = spot.distance_to($Campfire.position) > Balance.CAMP_SAFE_RADIUS + 8.0
		for actor in actors:
			if not actor.dead and spot.distance_to(actor.position) < Balance.MONSTER_SPAWN_CLEARANCE:
				clear = false
		if clear:
			break
	if not clear:
		return null
	var monster := MonsterScene.instantiate() as Node3D
	monster_serial += 1
	monster.name = "Monster%03d" % monster_serial
	monster.position = spot
	monsters.append(monster)
	add_child(monster)
	record_event("A monster appeared (%d HP)" % Balance.MONSTER_HEALTH)
	return monster


func _population_ready_for_monster() -> bool:
	var ready := 0
	for actor in actors:
		if not actor.dead and actor.health >= Balance.RECOVERED_HEALTH and actor.satiety > Balance.HUNGER_THRESHOLD and actor.hydration > Balance.THIRST_THRESHOLD:
			ready += 1
	return ready >= ceili(actors.size() * 2.0 / 3.0) and not actors.is_empty()


func monster_defeated(monster: Node3D) -> void:
	monsters.erase(monster)
	monster_spawn_clock = resource_rng.randf_range(Balance.MONSTER_SPAWN_SECONDS.x, Balance.MONSTER_SPAWN_SECONDS.y)
	record_event("Supply break: next monster in at least %ds" % ceili(monster_spawn_clock))


func record_event(message: String) -> void:
	events.push_front("%02d:%02d  %s" % [int(elapsed / 60.0), int(elapsed) % 60, message])
	if events.size() > 60:
		events.resize(60)


func make_hungry() -> void:
	if actors[selected_index].dead:
		return
	actors[selected_index].satiety = Balance.HUNGER_THRESHOLD
	actors[selected_index].hungry = true
	record_event("Hunger triggered: cook food, or eat raw meat when starving")


func make_starving() -> void:
	if actors[selected_index].dead:
		return
	actors[selected_index].satiety = Balance.STARVATION_THRESHOLD - 5.0
	actors[selected_index].hungry = true
	record_event("Starvation triggered: prioritize ready food or raw meat")


func make_thirsty() -> void:
	if actors[selected_index].dead:
		return
	actors[selected_index].hydration = Balance.THIRST_THRESHOLD
	actors[selected_index].thirsty = true
	record_event("Thirst triggered: collect water from a spring")


func toggle_speed() -> void:
	Engine.time_scale = 3.0 if Engine.time_scale == 1.0 else 1.0


func reset_demo() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func apply_population(count: int, config: Dictionary) -> void:
	stress.set_config(config, get_tree())
	set_agent_count(count)


func reset_performance() -> void:
	stress.reset_samples(actors)


func _track_resource(child: Node) -> void:
	if child is ResourceObject:
		resources.append(child)


func _untrack_resource(child: Node) -> void:
	if child is ResourceObject:
		unstore_item(child)
		resources.erase(child)


func _sync_source_resources() -> void:
	var scenes: Dictionary = {
		&"tree": TreeScene,
		&"animal": AnimalScene,
		&"spring": SpringScene,
		&"stone": StoneScene,
	}
	for kind: StringName in scenes:
		var phase := 0.0
		match kind:
			&"animal": phase = 0.23
			&"spring": phase = 0.47
			&"stone": phase = 0.71
		var sources: Array[Node3D] = []
		for resource in resources:
			if resource.kind == kind and not resource.harvest_method.is_empty():
				sources.append(resource)
		while sources.size() > agent_count:
			var removed: Node3D = sources.pop_back()
			extra_resources.erase(removed)
			remove_child(removed)
			removed.queue_free()
		while sources.size() < agent_count:
			var source := (scenes[kind] as PackedScene).instantiate() as Node3D
			resource_serial += 1
			source.name = "Generated%s%04d" % [String(kind).capitalize(), resource_serial]
			var index := sources.size()
			source.position = Map.clamp_position(Vector3(
				fposmod((index + 1) * 0.61803398875 + phase, 1.0) * 72.0 - 36.0,
				0,
				fposmod((index + 1) * 0.754877666 + phase, 1.0) * 48.0 - 24.0
			))
			extra_resources.append(source)
			sources.append(source)
			add_child(source)
			relocate_resource(source)


func _fit_map_to_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0:
		return
	camera.size = 44.16
	var map_width: float = hud.map_width()
	camera.position.x = camera.size * (viewport_size.x - map_width) / (2.0 * viewport_size.y)
	var floor_half := Vector2(camera.size * map_width / viewport_size.y / 2.0, 30.0)
	Map.half_size = floor_half - Vector2(2.0, 3.0)
	var ground := $Environment/Ground.mesh as BoxMesh
	ground.size = Vector3(floor_half.x * 2 + 4, 0.3, floor_half.y * 2 + 4)
	$Environment/Grid.scale = Vector3(floor_half.x / 14.0, 1, floor_half.y / 10.0)
	for actor in actors:
		actor.position = Map.clamp_position(actor.position)
	for resource in resources:
		resource.position = Map.clamp_position(resource.position)
		resource.home = resource.position
	for monster in monsters:
		monster.position = Map.clamp_position(monster.position)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	var inspector := get_node_or_null("/root/GoapInspector")
	if inspector != null:
		inspector.set_auto_show_monitor(true)
