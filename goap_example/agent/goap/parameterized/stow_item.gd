extends "res://goap_example/agent/goap/ability_action.gd"
## Carry each crafting material back separately before using the shared recipe.

const Facts = preload("res://goap_example/survival/fact_keys.gd")
var item: Resource


func configure(definition: Resource) -> void:
	item = definition.duplicate()
	name = StringName("Store " + item.title)
	preconditions = GoapWorldState.new({item.inventory_fact(): true, Facts.CARRYING_SUPPLIES: true})
	effects = GoapWorldState.new({item.inventory_fact(): false,
		Facts.CARRYING_SUPPLIES: false, Facts.AT_CAMP: true})
	match item.kind:
		&"wood": effects.set_state(Facts.CAMP_HAS_WOOD, true)
		&"stone_item": effects.set_state(Facts.CAMP_HAS_STONE, true)


func get_id() -> String:
	return "Store:" + item.signature()


func start(agent: GoapAgent) -> void:
	execution = agent.actor.stow_carried_goods()
