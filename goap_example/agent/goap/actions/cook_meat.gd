extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.cook_meat()


func _get_name() -> StringName:
	return &"CookMeat"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HAS_RAW_MEAT: true, Facts.HAS_FIRE: true, Facts.STARVING: false })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HAS_COOKED_MEAT: true, Facts.HAS_RAW_MEAT: false })
