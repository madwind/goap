extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func start(agent: GoapAgent) -> void:
	execution = agent.actor.attack()


func is_valid(agent: GoapAgent) -> bool:
	return not agent.actor.dead and not agent.actor.is_low_health() and not agent.actor.is_starving() and not agent.actor.is_dehydrated()


func _get_name() -> StringName:
	return &"AttackMonster"


func _get_preconditions() -> GoapWorldState:
	# Health is an immediate execution/goal gate. Regressing through healing here
	# would enumerate meals inside every weapon-crafting permutation.
	return GoapWorldState.new({ Facts.HAS_MONSTER: true, Facts.HAS_WEAPON: true, Facts.STARVING: false, Facts.DEHYDRATED: false })


func _get_effects() -> GoapWorldState:
	return GoapWorldState.new({ Facts.HAS_MONSTER: false })
