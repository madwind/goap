extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.light_fire()


func _get_name() -> StringName:
	return &"RekindleFire"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({ Facts.FIRE_LOW: true, Facts.HAS_WOOD: true, Facts.CAN_TEND_FIRE: true })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.FIRE_STABLE: true, Facts.HAS_FIRE: true, Facts.HAS_WOOD: false, Facts.CARRYING_SUPPLIES: false })
