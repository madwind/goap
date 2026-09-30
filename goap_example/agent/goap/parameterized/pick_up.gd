extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")

var item: Resource


func configure(definition: Resource) -> void:
	# Definitions belong to an immutable planning generation, not live scene data.
	item = definition.duplicate()
	name = StringName("Pick Up " + (item.title if not item.title.is_empty() else String(item.kind).capitalize()))
	preconditions = GoapWorldState.new({item.available_fact(): true, Facts.CARRYING_SUPPLIES: false})
	effects = GoapWorldState.new({item.inventory_fact(): true, item.available_fact(): false, Facts.CARRYING_SUPPLIES: true})


func get_id() -> String:
	return "PickUp:" + item.signature()


func start(agent: GoapAgent) -> void:
	execution = agent.actor.pick_up(item, null, agent.is_resource_observed)


func nearest_target_distance(agent: GoapAgent) -> float:
	var signature: String = item.signature()
	var target: Node3D = agent.find_observed_resource(item.kind, func(resource: Node3D) -> bool:
		return resource.item != null and resource.item.signature() == signature
	)
	return agent.actor.global_position.distance_squared_to(target.global_position) if target != null else INF
