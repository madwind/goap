extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.drink_water()


func is_valid(agent: GoapAgent) -> bool:
	return agent == null or agent.actor.thirsty


func _get_name() -> StringName:
	return &"DrinkWater"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({Facts.HAS_WATER: true})


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({Facts.THIRSTY: false, Facts.HAS_WATER: false, Facts.CARRYING_SUPPLIES: false})
