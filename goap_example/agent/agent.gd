extends CharacterBody3D

const Balance = preload("res://goap_example/survival/balance.gd")
const Map = preload("res://goap_example/survival/map.gd")
const ResourceObject = preload("res://goap_example/resources/resource.gd")
const Execution = preload("res://goap_example/agent/abilities/execution.gd")
const Harvesting = preload("res://goap_example/agent/abilities/harvesting.gd")
const Cooking = preload("res://goap_example/agent/abilities/cooking.gd")
const Feeding = preload("res://goap_example/agent/abilities/feeding.gd")
const Combat = preload("res://goap_example/agent/abilities/combat.gd")
const Equipment = preload("res://goap_example/agent/abilities/equipment.gd")
const Storage = preload("res://goap_example/agent/abilities/storage.gd")
const ALERT_RADIUS := 8.0
const RAW_NUTRITION := Balance.RAW_NUTRITION
const COOKED_NUTRITION := Balance.COOKED_NUTRITION
var movement_speed := 3.2
var _ground_steering: Dictionary = {}
var satiety := Balance.INITIAL_SATIETY
var hunger_rate := Balance.HUNGER_RATE
var hungry := false
var hydration := Balance.INITIAL_HYDRATION
var thirst_rate := Balance.THIRST_RATE
var thirsty := false
var dead := false
var selected := false
var health := Balance.AGENT_HEALTH
var recovering := false
var retreating := false
var respawn_remaining := 0.0
var deaths := 0
# The carried scene object is the only source of inventory truth.
var carried_item: Node3D
var raw_meat: bool:
	get: return has_item(&"raw_meat")
var cooked_meat: bool:
	get: return has_item(&"cooked_meat")
var wood: bool:
	get: return has_item(&"wood")
var water: bool:
	get: return has_item(&"water")
var stone: bool:
	get: return has_item(&"stone")
var weapon_durability := 0
var weapons_crafted := 0
var drinks := 0
var activity := "Observing surroundings"
var meals := 0
var raw_meals := 0
var cooked_meals := 0
var _active_ability: Execution
var _deprivation_damage := 0.0


func _physics_process(delta: float) -> void:
	if dead:
		respawn_remaining = maxf(0.0, respawn_remaining - delta)
		if respawn_remaining <= 0:
			_respawn()
		return
	satiety = maxf(0, satiety - hunger_rate * delta)
	hydration = maxf(0, hydration - thirst_rate * delta)
	var depleted_needs := int(satiety <= 0.0) + int(hydration <= 0.0)
	if depleted_needs > 0:
		_deprivation_damage += delta * Balance.DEPRIVATION_DAMAGE_PER_SECOND * depleted_needs
		var damage := int(_deprivation_damage)
		if damage > 0:
			_deprivation_damage -= damage
			take_damage(damage)
			if dead:
				return
	else:
		_deprivation_damage = 0.0
	if satiety <= Balance.HUNGER_THRESHOLD:
		hungry = true
	if hydration <= Balance.THIRST_THRESHOLD:
		thirsty = true
	if health <= Balance.LOW_HEALTH_THRESHOLD:
		recovering = true
	elif health >= Balance.RECOVERED_HEALTH:
		recovering = false
	retreating = is_in_danger() and is_low_health()
	if _active_ability != null:
		_active_ability.advance(delta)
		if _active_ability.state != Execution.State.RUNNING:
			_active_ability = null
	if _active_ability == null:
		activity = "Waiting for resources" if hungry or thirsty else "Resting"


func has_item(key: StringName) -> bool:
	return is_instance_valid(carried_item) and not carried_item.is_queued_for_deletion() \
		and carried_item.item.inventory_key == key


func carried_items() -> PackedStringArray:
	return PackedStringArray([carried_item.item.title]) if has_held_goods() else PackedStringArray()


func has_held_goods() -> bool:
	return is_instance_valid(carried_item) and not carried_item.is_queued_for_deletion()


func can_carry_item() -> bool:
	return not has_held_goods()


func stow_carried_goods() -> Execution:
	return _begin_ability(Storage.stow(self, get_camp()))


func deposit_item() -> void:
	if not has_held_goods():
		return
	var model := carried_item
	carried_item = null
	get_camp().store_item(model)


func take_item_model(target: Node3D) -> bool:
	if not can_carry_item() or not is_instance_valid(target) or target.is_queued_for_deletion() \
		or not target.available or target.item == null:
		return false
	get_camp().remove_item(target)
	target.available = false
	target.in_transit = true
	target.reparent($CarriedGoods)
	target.position = Vector3(0, 1.05, 0.48)
	carried_item = target
	return true


func consume_item(key: StringName) -> bool:
	if not has_item(key):
		return false
	carried_item.queue_free()
	carried_item = null
	return true


func cook_carried_meat() -> void:
	if raw_meat:
		carried_item.item = preload("res://goap_example/resources/cooked_meat.tres")
		carried_item.update_item_visual()


func drop_carried_item() -> void:
	if not has_held_goods():
		return
	var model := carried_item
	carried_item = null
	model.reparent(get_parent())
	model.position = Map.clamp_position(position + Vector3(0.7, 0, 0))
	model.in_transit = false
	model.available = true


func move_to(target: Vector3, speed_multiplier := 1.0) -> void:
	if dead:
		return
	var waypoint := target
	var camp := get_camp()
	if camp != null:
		waypoint = Map.camp_waypoint(global_position, target, camp.global_position, _ground_steering)
	var direction := waypoint - global_position
	direction.y = 0
	Map.move_on_ground(self, direction, movement_speed * speed_multiplier, _ground_steering)
	position = Map.clamp_position(position)


func approach(target: Vector3, interaction_radius := 1.6) -> bool:
	if global_position.distance_to(target) > interaction_radius:
		move_to(target)
		return false
	stop_moving()
	return true


func stop_moving() -> void:
	velocity = Vector3.ZERO
	_ground_steering.clear()


func find_resource(kind: StringName) -> Node3D:
	return get_parent().nearest(kind, global_position)


func find_matching_resource(kind: StringName, filter: Callable) -> Node3D:
	var found: Node3D
	var distance := INF
	var candidates: Array = get_parent().resources if "resources" in get_parent() else get_parent().get_children()
	for candidate in candidates:
		if not candidate is ResourceObject:
			continue
		if candidate.kind != kind or not candidate.available or not filter.call(candidate):
			continue
		var candidate_distance: float = global_position.distance_squared_to(candidate.global_position)
		if candidate_distance < distance:
			found = candidate
			distance = candidate_distance
	return found


func harvest(target: Node3D = null, kind: StringName = &"", profile := "", candidate_filter := Callable()) -> Execution:
	var automatic := target == null
	if target != null:
		kind = target.kind
		profile = target.harvest_profile() if profile.is_empty() else profile
	return _begin_ability(Harvesting.harvest(self, target, kind, profile, automatic, candidate_filter))


func pick_up(item: Resource, target: Node3D = null, candidate_filter := Callable()) -> Execution:
	return _begin_ability(Harvesting.pick_up(self, item, target, target == null, candidate_filter))


func get_camp() -> Node3D:
	return get_parent().get_node_or_null("Campfire")


func is_at_camp() -> bool:
	if not is_inside_tree():
		return false
	var camp := get_camp()
	return camp != null and global_position.distance_to(camp.global_position) <= float(camp.get_meta(&"interaction_radius", 1.6))


func has_stable_fire() -> bool:
	return is_inside_tree() and get_camp().has_stable_fire()


func get_threat() -> Node3D:
	if dead:
		return null
	var world := get_parent()
	if world.has_method("shared_monster_alert"):
		var shared: Node3D = world.shared_monster_alert()
		if shared != null:
			return shared
	return world.nearest_monster(global_position, ALERT_RADIUS)


func is_low_health() -> bool:
	return health <= Balance.LOW_HEALTH_THRESHOLD or recovering and health < Balance.RECOVERED_HEALTH


func is_in_danger() -> bool:
	var camp := get_camp()
	if camp != null and global_position.distance_to(camp.global_position) <= Balance.CAMP_SAFE_RADIUS:
		return false
	var nearby_threat: bool = get_parent().nearest_monster(global_position, Balance.FLEE_START_RADIUS) != null
	var threat_in_escape_range: bool = get_parent().nearest_monster(global_position, Balance.FLEE_CLEAR_RADIUS) != null
	# Keep fleeing until there is room to recover, rather than turning back at 6 units.
	return (is_low_health() and threat_in_escape_range and retreating) or nearby_threat


func take_damage(amount: int) -> void:
	if dead:
		return
	health = maxi(0, health - maxi(1, amount))
	get_parent().record_event("%s took %d damage (%d HP)" % [name, amount, health])
	if health == 0:
		_die()


func heal(amount: int) -> void:
	if not dead:
		health = mini(Balance.AGENT_HEALTH, health + maxi(0, amount))


func is_starving() -> bool:
	return satiety <= Balance.STARVATION_THRESHOLD


func is_dehydrated() -> bool:
	return hydration <= Balance.DEHYDRATION_THRESHOLD


func has_fire() -> bool:
	return get_camp().has_fire()


func chop_tree(tree: Node3D = null) -> Execution:
	var automatic := tree == null
	if tree == null:
		tree = find_resource(&"tree")
	return _begin_ability(Harvesting.harvest(self, tree, &"tree", tree.harvest_profile() if tree != null else "", automatic))


func hunt_animal(animal: Node3D = null) -> Execution:
	var automatic := animal == null
	if animal == null:
		animal = find_resource(&"animal")
	return _begin_ability(Harvesting.harvest(self, animal, &"animal", animal.harvest_profile() if animal != null else "", automatic))


func pick_up_meat(meat: Node3D = null) -> Execution:
	return pick_up(preload("res://goap_example/resources/raw_meat.tres"), meat)


func light_fire(camp: Node3D = null) -> Execution:
	if camp == null:
		camp = get_camp()
	return _begin_ability(Cooking.light_fire(self, camp))


func cook_meat(camp: Node3D = null) -> Execution:
	if camp == null:
		camp = get_camp()
	return _begin_ability(Cooking.cook_meat(self, camp))


func eat_raw_meat() -> Execution:
	return _begin_ability(Feeding.eat_raw_meat(self))


func eat_cooked_meat() -> Execution:
	return _begin_ability(Feeding.eat_cooked_meat(self))


func drink_water() -> Execution:
	return _begin_ability(Feeding.drink_water(self))


func craft_weapon() -> Execution:
	return _begin_ability(Equipment.craft_weapon(self, get_parent().get_node("CampFence/Workbench")))


func finish_weapon() -> bool:
	if dead or weapon_durability > 0:
		return false
	var bench: Node3D = get_camp().workbench()
	if bench == null or global_position.distance_to(bench.global_position) > float(bench.get_meta(&"interaction_radius", 2.0)):
		return false
	if not get_camp().consume_crafting_materials():
		return false
	weapon_durability = Balance.WEAPON_DURABILITY
	weapons_crafted += 1
	$Weapon.visible = true
	get_parent().record_event("%s crafted a stone axe (%d durability)" % [name, weapon_durability])
	return true


func use_weapon_hit() -> int:
	if weapon_durability == 0:
		return Balance.UNARMED_DAMAGE
	weapon_durability -= 1
	if weapon_durability == 0:
		$Weapon.hide()
		get_parent().record_event("%s's stone axe broke" % name)
	return Balance.WEAPON_DAMAGE


func use_weapon_hunt_hit() -> int:
	if weapon_durability == 0:
		return 1
	weapon_durability -= 1
	if weapon_durability == 0:
		$Weapon.hide()
		get_parent().record_event("%s's stone axe broke" % name)
	return Balance.WEAPON_ANIMAL_DAMAGE


func drink() -> void:
	if dead or not water:
		return
	consume_item(&"water")
	hydration = minf(100.0, hydration + Balance.WATER_RESTORATION)
	thirsty = false
	drinks += 1
	get_parent().record_event("Drank water; hydration +%d" % int(Balance.WATER_RESTORATION))


func attack(target: Node3D = null) -> Execution:
	if target == null:
		target = get_threat()
	return _begin_ability(Combat.attack(self, target))


func flee_monster() -> Execution:
	return _begin_ability(Combat.flee_monster(self))


func rest_at_camp() -> Execution:
	return _begin_ability(Combat.rest_at_camp(self, get_camp()))


func eat(cooked: bool) -> void:
	if dead or not (cooked_meat if cooked else raw_meat):
		return
	satiety = minf(100, satiety + (COOKED_NUTRITION if cooked else RAW_NUTRITION))
	heal(Balance.COOKED_HEAL if cooked else Balance.RAW_HEAL)
	hungry = false
	meals += 1
	if cooked:
		consume_item(&"cooked_meat")
		cooked_meals += 1
	else:
		consume_item(&"raw_meat")
		raw_meals += 1
	get_parent().record_event(
		"Ate %s; satiety +%d, health +%d" % [
			"cooked meat" if cooked else "raw meat",
			COOKED_NUTRITION if cooked else RAW_NUTRITION,
			Balance.COOKED_HEAL if cooked else Balance.RAW_HEAL
		]
	)


func _begin_ability(next: Execution) -> Execution:
	if dead:
		next.cancel()
		return next
	if _active_ability != null:
		_active_ability.cancel()
	_active_ability = next
	next.start()
	activity = next.label
	return next


func _exit_tree() -> void:
	if _active_ability != null:
		_active_ability.cancel()


func _die() -> void:
	drop_carried_item()
	dead = true
	deaths += 1
	health = 0
	respawn_remaining = Balance.RESPAWN_SECONDS
	activity = "Dead"
	if _active_ability != null:
		_active_ability.cancel()
		_active_ability = null
	stop_moving()
	var controller := get_node_or_null("GoapAgent")
	if controller != null:
		controller.suspend()
	$Body.hide()
	$Weapon.hide()
	$DeathMarker.show()
	$AlertRing.hide()
	$CollisionShape3D.set_deferred("disabled", true)
	get_parent().record_event("%s died; respawning in 5 seconds" % name)


func _respawn() -> void:
	dead = false
	health = Balance.AGENT_HEALTH
	recovering = false
	retreating = false
	respawn_remaining = 0.0
	satiety = Balance.INITIAL_SATIETY
	hydration = Balance.INITIAL_HYDRATION
	hungry = false
	thirsty = false
	_deprivation_damage = 0.0
	carried_item = null
	weapon_durability = 0
	$Weapon.hide()
	activity = "Observing surroundings"
	$DeathMarker.hide()
	$Body.show()
	$AlertRing.visible = selected
	$CollisionShape3D.set_deferred("disabled", false)
	var controller := get_node_or_null("GoapAgent")
	if controller != null:
		controller.resume_after_respawn()
	get_parent().record_event("%s respawned with %d satiety" % [name, ceili(satiety)])
