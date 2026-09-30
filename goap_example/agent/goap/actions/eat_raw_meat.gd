extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_cost_model() -> GDScript:
	return preload("res://goap_example/agent/goap/costs/raw_meat_cost.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.eat_raw_meat()


func is_valid(agent: GoapAgent) -> bool:
	return agent == null or agent.actor.hungry or agent.actor.is_low_health()


func _get_name() -> StringName:
	return &"EatRawMeat"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HAS_RAW_MEAT: true })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HUNGRY: false, Facts.HAS_RAW_MEAT: false, Facts.LOW_HEALTH: false, Facts.CARRYING_SUPPLIES: false })
