extends Node3D
## Owns shared stock, recipes and the one operation allowed to tend the fire.

const Balance = preload("res://goap_example/survival/balance.gd")
const STOCK_LIMIT := 8
const STOCK_KINDS: Array[StringName] = [&"wood", &"stone_item", &"water", &"meat"]
var fire_remaining := 0.0
var _stock: Array[Node3D] = []
var _fire_tender: WeakRef
var _fire_operation: WeakRef
var _time := 0.0


func _physics_process(delta: float) -> void:
	_time += delta
	var burning := has_fire()
	fire_remaining = maxf(0.0, fire_remaining - delta)
	if burning and not has_fire():
		get_parent().record_event("Campfire went out; gather wood to light it again")
	$Flame.visible = has_fire()
	$Flame.scale.y = 1.0 + sin(_time * 9.0) * 0.12
	$Caption.text = "Campfire · %ds" % ceili(fire_remaining) if has_fire() else "Campfire · Needs wood"
	if has_stable_fire():
		_fire_tender = null
	else:
		_update_fire_tender()


func has_fire() -> bool:
	return fire_remaining > 0.0


func has_stable_fire() -> bool:
	return fire_remaining > Balance.FIRE_RELIGHT_THRESHOLD


func workbench() -> Node3D:
	return get_parent().get_node("CampFence/Workbench")


func stock_count(kind: StringName) -> int:
	var count := 0
	for model in _stock:
		if _usable_stock(model) and model.kind == kind:
			count += 1
	return count


func stockpile_full() -> bool:
	return STOCK_KINDS.all(func(kind: StringName) -> bool: return stock_count(kind) >= STOCK_LIMIT)


func has_crafting_materials() -> bool:
	return stock_count(&"wood") > 0 and stock_count(&"stone_item") > 0


func consume_crafting_materials() -> bool:
	var timber := _first_stock(&"wood")
	var stone := _first_stock(&"stone_item")
	if timber == null or stone == null:
		return false
	# Validate both before changing either; completion runs on the main thread.
	for model in [timber, stone]:
		remove_item(model)
		model.available = false
		model.queue_free()
	return true


func store_item(model: Node3D) -> void:
	if not is_instance_valid(model) or model.is_queued_for_deletion() or _stock.has(model):
		return
	model.reparent(get_parent())
	model.in_transit = false
	model.available = true
	model.stored_at_camp = true
	_stock.append(model)
	_arrange_stock(model.kind)
	get_parent().record_event("%s delivered to camp" % model.item.title)


func remove_item(model: Node3D) -> void:
	if not _stock.has(model):
		return
	_stock.erase(model)
	model.stored_at_camp = false
	_arrange_stock(model.kind)


func _usable_stock(model: Node3D) -> bool:
	return is_instance_valid(model) and not model.is_queued_for_deletion() and model.stored_at_camp and model.available


func _first_stock(kind: StringName) -> Node3D:
	for model in _stock:
		if _usable_stock(model) and model.kind == kind:
			return model
	return null


func _arrange_stock(kind: StringName) -> void:
	var storage := "MeatStorage"
	match kind:
		&"wood": storage = "WoodStorage"
		&"stone_item": storage = "StoneStorage"
		&"water": storage = "WaterStorage"
	var marker := get_parent().get_node("CampFence/" + storage) as Node3D
	var slot := 0
	for model in _stock:
		if _usable_stock(model) and model.kind == kind:
			model.global_position = marker.global_position + Vector3(slot % 4 * 0.72, 0.08 if kind == &"meat" else 0.0, slot / 4 * 0.72)
			slot += 1


func can_tend_fire(actor: Node3D) -> bool:
	if has_stable_fire():
		return false
	var running: Object = _fire_operation.get_ref() if _fire_operation != null else null
	if running != null:
		return running.actor == actor
	var tender: Node3D = _fire_tender.get_ref() if _fire_tender != null else null
	return tender == actor and _eligible_tender(tender)


func _update_fire_tender() -> void:
	var running: Object = _fire_operation.get_ref() if _fire_operation != null else null
	if running != null:
		return
	var tender: Node3D = _fire_tender.get_ref() if _fire_tender != null else null
	if not _eligible_tender(tender):
		tender = _choose_tender()
		_fire_tender = weakref(tender) if tender != null else null


func claim_fire(operation: RefCounted) -> bool:
	if has_stable_fire():
		return false
	_update_fire_tender()
	if not can_tend_fire(operation.actor):
		return false
	var running: Object = _fire_operation.get_ref() if _fire_operation != null else null
	if running != null and running != operation:
		return false
	_fire_operation = weakref(operation)
	return true


func release_fire(operation: RefCounted) -> void:
	if _fire_operation != null and _fire_operation.get_ref() == operation:
		_fire_operation = null
		_fire_tender = null


func finish_fire(operation: RefCounted) -> bool:
	if _fire_operation == null or _fire_operation.get_ref() != operation or has_stable_fire():
		return false
	if not operation.actor.consume_item(&"wood"):
		return false
	fire_remaining = Balance.FIRE_SECONDS
	get_parent().record_event("Used 1 wood; campfire lit for %d seconds" % Balance.FIRE_SECONDS)
	return true


func _eligible_tender(actor: Node3D) -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_queued_for_deletion() \
		and not actor.dead and not actor.is_low_health() and not actor.hungry and not actor.thirsty \
		and actor.get_threat() == null and not actor.get_node("GoapAgent").is_suspended


func _choose_tender() -> Node3D:
	var chosen: Node3D
	var best := INF
	for candidate in get_parent().actors:
		if not _eligible_tender(candidate):
			continue
		var score: float = candidate.global_position.distance_squared_to(global_position)
		if candidate.wood:
			score -= 10000.0
		elif candidate.has_held_goods():
			score += 10000.0
		if score < best:
			chosen = candidate
			best = score
	return chosen
