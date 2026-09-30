extends GoapAgent

const Balance = preload("res://goap_example/survival/balance.gd")
const Facts = preload("res://goap_example/survival/fact_keys.gd")
const HarvestAction = preload("res://goap_example/agent/goap/parameterized/harvest.gd")
const PickUpAction = preload("res://goap_example/agent/goap/parameterized/pick_up.gd")
const StowItemAction = preload("res://goap_example/agent/goap/parameterized/stow_item.gd")
const ReplenishAction = preload("res://goap_example/agent/goap/parameterized/replenish.gd")
const ResourceObject = preload("res://goap_example/resources/resource.gd")
const ResourceProvider = preload("res://goap_example/resources/resource_state_provider.gd")
const ActorProvider = preload("res://goap_example/agent/goap/actor_state_provider.gd")
const Actor = preload("res://goap_example/agent/agent.gd")
const Execution = preload("res://goap_example/agent/abilities/execution.gd")
var _harvest_actions: Dictionary = {}
var _pickup_actions: Dictionary = {}
var _preview_actor_facts: Dictionary = {}
var _observed_resources: Dictionary = {}
var _display_cost_plan: GoapPlan
var _display_cost_labels: Array[String] = []


func load_goap_actions(script_folder: String) -> void:
	super.load_goap_actions(script_folder)
	_harvest_actions.clear()
	_pickup_actions.clear()
	_preview_actor_facts.clear()
	if is_inside_tree():
		return # Runtime definitions come exclusively from discovered providers.
	# Detached editor previews have no world to observe. Read the authored resource
	# scenes, so their initial graph uses the very same drop configurations.
	for scene in [preload("res://goap_example/resources/tree.tscn"), preload("res://goap_example/resources/animal.tscn"), preload("res://goap_example/resources/spring.tscn"), preload("res://goap_example/resources/stone.tscn")]:
		var authored: Node3D = scene.instantiate()
		# Scene scripts are placeholders in the editor; use an explicit data reader.
		var resource := ResourceObject.new()
		resource.kind = authored.kind
		resource.harvest_method = authored.harvest_method
		resource.drops = authored.drops
		_discover_resource(resource)
		resource.free()
		authored.free()
	for action in _harvest_actions.values():
		world_state.set_state(action.available_fact, true)
	for action in _pickup_actions.values():
		world_state.set_state(action.item.available_fact(), false)
	var preview_actor := Actor.new()
	var actor_facts: GoapWorldState = ActorProvider.state_from_actor(preview_actor)
	world_state.merge(actor_facts, false)
	for key in actor_facts.keys():
		_preview_actor_facts[key] = true
	preview_actor.free()


func _discover_resource(resource: Node3D) -> bool:
	var changed := false
	if not resource.harvest_method.is_empty() and resource.has_harvest_drops():
		var profile: String = resource.harvest_profile()
		if not _harvest_actions.has(profile):
			var action := HarvestAction.new()
			action.configure(resource)
			var title := String(action.name)
			for other in _harvest_actions.values():
				if other.display_name == action.display_name:
					other.name = StringName("%s (%s)" % [title, other.profile.get_slice(":", 1)])
					action.name = StringName("%s (%s)" % [title, profile.get_slice(":", 1)])
			_harvest_actions[profile] = action
			actions.append(action)
			changed = true
	for item in resource.drops + [resource.item]:
		if item == null:
			continue
		var signature: String = item.signature()
		if not _pickup_actions.has(signature):
			var action := PickUpAction.new()
			action.configure(item)
			_pickup_actions[signature] = action
			actions.append(action)
			var store := StowItemAction.new()
			store.configure(item)
			actions.append(store)
			if item.kind in [&"wood", &"stone_item", &"water", &"meat"]:
				var replenish := ReplenishAction.new()
				replenish.configure(item)
				actions.append(replenish)
			changed = true
	return changed


func _physics_process(delta: float) -> void:
	if is_suspended or actor.dead:
		return
	# Observe completion before publishing consumed ingredients as new facts.
	# Otherwise replanning could invalidate an action that has already succeeded.
	var generation_before := planning_generation
	super._physics_process(delta)
	# A peer can create ground items while this agent is travelling to harvest.
	# The observation above must stop that now-invalid trip before the next
	# budgeted planning request finishes.
	if not is_suspended and planning_generation != generation_before:
		discard_invalid_plan()


func get_world_state_label(key: StringName) -> String:
	for action in _harvest_actions.values():
		if action.available_fact != key:
			continue
		var variants := 0
		var same_method := 0
		for other in _harvest_actions.values():
			if other.available_label == action.available_label:
				variants += 1
			if other.method_label == action.method_label:
				same_method += 1
		if variants > 1:
			return action.full_label if same_method > 1 else action.method_label
		return action.available_label
	for action in _pickup_actions.values():
		if action.item.available_fact() == key:
			var title: String = action.item.title if not action.item.title.is_empty() else String(action.item.kind).capitalize()
			for other in _pickup_actions.values():
				if other != action and other.item.title == action.item.title:
					return "%s on ground (%s)" % [title, action.item.signature()]
			return "%s on ground" % title
	return super.get_world_state_label(key)


func get_world_state_sources(key: StringName) -> Array[Dictionary]:
	if _preview_actor_facts.has(key):
		return _provider_source("res://goap_example/agent/goap/actor_state_provider.gd", "state_from_actor")
	for action in _harvest_actions.values():
		if action.available_fact == key:
			return _provider_source("res://goap_example/resources/resource_state_provider.gd")
	for action in _pickup_actions.values():
		if action.item.available_fact() == key:
			return _provider_source("res://goap_example/resources/resource_state_provider.gd")
	return super.get_world_state_sources(key)


func _provider_source(path: String, method := "get_world_state") -> Array[Dictionary]:
	var sources: Array[Dictionary] = [
		{ "label": "WorldStateProvider", "path": path, "method": method }
	]
	return sources


func resume_after_respawn() -> void:
	refresh_world_state()
	resume()


## Discover all provider types in this world, plus this actor's private providers.
## Filter WORLD providers here for local senses; keep the actor's own providers.
func _discover_world_state_providers() -> Array[GoapWorldStateProvider]:
	var providers := GoapWorldStateProvider.discover(actor.get_parent(), self)
	var result: Array[GoapWorldStateProvider] = []
	var nearest: Dictionary = {}
	var scores: Dictionary = {}
	var usable: Dictionary = {}
	for provider in providers:
		if not provider is ResourceProvider:
			result.append(provider)
			continue
		var resource: Node3D = provider.get_parent()
		var identities: Array[String] = []
		if not resource.harvest_method.is_empty() and resource.has_harvest_drops():
			identities.append("harvest:" + resource.harvest_profile())
		if resource.item != null:
			identities.append("item:" + resource.item.signature())
		var score: float = actor.global_position.distance_squared_to(resource.global_position)
		for identity in identities:
			var can_use: bool = resource.available if identity.begins_with("item:") else resource.can_harvest(actor)
			if not scores.has(identity) or (can_use and not usable[identity]) or (can_use == usable[identity] and score < float(scores[identity])):
				scores[identity] = score
				usable[identity] = can_use
				nearest[identity] = provider
	for identity in nearest:
		var provider: ResourceProvider = nearest[identity]
		if not result.has(provider):
			result.append(provider)
	return result


func _observe_world_state() -> GoapWorldState:
	var providers := _discover_world_state_providers()
	_observed_resources.clear()
	for provider in providers:
		if not is_instance_valid(provider) or not provider.is_inside_tree() or provider.is_queued_for_deletion():
			continue
		if provider is ResourceProvider:
			_observed_resources[provider.get_parent().get_instance_id()] = provider
			_discover_resource(provider.get_parent())
	return GoapWorldStateProvider.collect(providers, self)


func _should_replan_after_observation(before: Dictionary[StringName, bool], after: GoapWorldState) -> bool:
	if current_plan == null or current_goal == null:
		return true
	if not current_plan.is_valid_from(after):
		return true
	var previous := GoapWorldState.new(before)
	var urgency := goal_priority(current_goal, after)
	if urgency <= 0.0 or not current_goal.is_valid(after) or after.satisfies(current_goal.goal_state) \
		or urgency != goal_priority(current_goal, previous):
		return true
	for goal in goals:
		if goal != current_goal and goal.is_valid(after) and not after.satisfies(goal.goal_state) \
			and goal_priority(goal, after) > urgency:
			return true
	# A newly reachable drop can shorten an acquisition trip. Other shared
	# changes do not restart a still-valid action or its work timer.
	if current_action == null or not current_action.get_id().begins_with("Harvest:"):
		return false
	var execution: Execution = current_action.get("execution")
	if execution == null or not is_instance_valid(execution.target):
		return false
	var target_distance_squared: float = actor.global_position.distance_squared_to(execution.target.global_position)
	for key in after.keys():
		if before.get(key, false) == after.get_state(key):
			continue
		if not String(key).begins_with("item_available:") or not after.get_state(key):
			continue
		var signature := String(key).trim_prefix("item_available:")
		var pickup: PickUpAction = _pickup_actions.get(signature)
		if pickup == null:
			continue
		var item_distance_squared: float = pickup.nearest_target_distance(self)
		if is_finite(item_distance_squared) and item_distance_squared <= target_distance_squared:
			return true
	return false


## Both cost capture and ability execution use the same perception boundary.
func is_resource_observed(resource: Node3D) -> bool:
	if not is_instance_valid(resource) or resource.is_queued_for_deletion() or resource.get_parent() != actor.get_parent():
		return false
	var provider := resource.get_node_or_null("WorldStateProvider") as ResourceProvider
	if not is_instance_valid(provider) or not provider.is_inside_tree() or provider.is_queued_for_deletion():
		return false
	if _observed_resources.has(resource.get_instance_id()):
		return true
	for value in _observed_resources.values():
		if not is_instance_valid(value):
			continue
		var observed: ResourceProvider = value
		if not observed.is_inside_tree():
			continue
		var source: Node3D = observed.get_parent()
		if source.item != null and resource.item != null and source.item.signature() == resource.item.signature():
			return true
		if not source.harvest_method.is_empty() and source.has_harvest_drops() and source.harvest_profile() == resource.harvest_profile():
			return true
	return false


func find_observed_resource(kind: StringName, filter: Callable) -> Node3D:
	return actor.find_matching_resource(kind, func(resource: Node3D) -> bool:
		return is_resource_observed(resource) and filter.call(resource)
	)


func _capture_cost_state() -> Dictionary:
	return {
		Facts.STARVING: actor.satiety <= Balance.STARVATION_THRESHOLD,
		Facts.LOW_HEALTH: actor.is_low_health(),
	}


## Example-only display estimate. Keep it fixed for the lifetime of this plan.
func get_plan_cost_labels(plan: GoapPlan) -> Array[String]:
	if plan == null:
		return []
	if _display_cost_plan == plan:
		return _display_cost_labels.duplicate()
	_display_cost_plan = plan
	_display_cost_labels = _estimate_action_cost_labels(plan.actions)
	return _display_cost_labels.duplicate()


## Re-estimate a recorded route using the same example-only cost model as Plan Steps.
func get_route_cost_labels(action_ids: Array) -> Array[String]:
	var by_id: Dictionary = {}
	for action in actions:
		by_id[action.get_id()] = action
	if current_plan != null:
		for action in current_plan.actions:
			by_id[action.get_id()] = action
	var route: Array[GoapAction] = []
	for id in action_ids:
		if not by_id.has(id):
			return []
		route.append(by_id[id])
	return _estimate_action_cost_labels(route)


func _estimate_action_cost_labels(route: Array[GoapAction]) -> Array[String]:
	var labels: Array[String] = []
	var simulation := _capture_cost_state()
	for action in route:
		var model: GDScript = action.get_cost_model() if action.has_method("get_cost_model") else GoapCostModel
		var context: Dictionary = action.capture_context(self) if action.has_method("capture_context") else {}
		var total: float = action.cost if model == GoapCostModel else model.get_cost(simulation, context)
		if is_finite(total) and total >= 0.0:
			labels.append("Est. Action cost %.2f" % total)
		else:
			labels.append("")
		if model != GoapCostModel:
			model.apply_cost_effect(simulation, context)
	return labels
