extends GoapWorldStateProvider
## The actor's own knowledge: carried goods, needs, danger and its fire assignment.
## No facts are assembled by the agent or inferred from its action list.

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func _init() -> void:
	scope = Scope.ACTOR


func get_world_state(agent: GoapAgent) -> GoapWorldState:
	var actor := get_parent()
	if agent.actor != actor:
		return GoapWorldState.new()
	return state_from_actor(actor, actor.get_threat() != null)


## The detached editor preview uses the actor's script defaults with no world.
static func state_from_actor(actor: Node, threat_present := false) -> GoapWorldState:
	var low_health: bool = actor.is_low_health()
	var in_danger: bool = actor.is_in_danger() if actor.is_inside_tree() else false
	var at_camp: bool = actor.is_at_camp()
	var state := GoapWorldState.new({
		Facts.HUNGRY: actor.hungry,
		Facts.STARVING: actor.is_starving(),
		Facts.THIRSTY: actor.thirsty,
		Facts.DEHYDRATED: actor.is_dehydrated(),
		Facts.HAS_WATER: actor.water,
		Facts.HAS_RAW_MEAT: actor.raw_meat,
		Facts.HAS_COOKED_MEAT: actor.cooked_meat,
		Facts.HAS_WOOD: actor.wood,
		Facts.HAS_STONE: actor.stone,
		Facts.HAS_WEAPON: actor.weapon_durability > 0,
		Facts.CAN_TEND_FIRE: actor.is_inside_tree() and actor.get_camp().can_tend_fire(actor),
		Facts.HAS_MONSTER: threat_present,
		Facts.LOW_HEALTH: low_health,
		Facts.IN_DANGER: in_danger,
		Facts.AT_CAMP: at_camp,
		Facts.CARRYING_SUPPLIES: not actor.can_carry_item(),
		Facts.NEEDS_REST: actor.is_inside_tree() and not at_camp and not actor.hungry and not actor.thirsty
			and not low_health and not in_danger and not threat_present,
	})
	if actor.has_held_goods():
		state.set_state(actor.carried_item.item.inventory_fact(), true)
	return state
