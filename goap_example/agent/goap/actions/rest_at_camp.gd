extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.rest_at_camp()


func _get_name() -> StringName:
	return &"RestAtCamp"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({ Facts.NEEDS_REST: true, Facts.AT_CAMP: false })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.AT_CAMP: true, Facts.NEEDS_REST: false })
