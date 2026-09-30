extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.flee_monster()


func _get_name() -> StringName:
	return &"FleeMonster"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({ Facts.LOW_HEALTH: true, Facts.IN_DANGER: true })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.IN_DANGER: false })
