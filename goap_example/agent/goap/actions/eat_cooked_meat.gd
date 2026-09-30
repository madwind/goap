extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.eat_cooked_meat()


func is_valid(agent: GoapAgent) -> bool:
	return agent == null or agent.actor.hungry or agent.actor.is_low_health()


func _get_name() -> StringName:
	return &"EatCookedMeat"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HAS_COOKED_MEAT: true })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HUNGRY: false, Facts.HAS_COOKED_MEAT: false, Facts.LOW_HEALTH: false, Facts.CARRYING_SUPPLIES: false })
