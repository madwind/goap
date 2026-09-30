extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.craft_weapon()


func _get_name() -> StringName:
	return &"CraftWeapon"


func _get_preconditions() -> GoapWorldState:
	return GoapWorldState.new({Facts.CAMP_HAS_WOOD: true, Facts.CAMP_HAS_STONE: true, Facts.HAS_WEAPON: false})


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({Facts.CAMP_HAS_WOOD: false, Facts.CAMP_HAS_STONE: false, Facts.HAS_WEAPON: true})
