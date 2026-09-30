extends GoapWorldStateProvider
## Shared facts come from the camp's physical stock and timer.

const Facts = preload("res://goap_example/survival/fact_keys.gd")


func get_world_state(_agent: GoapAgent) -> GoapWorldState:
	var camp := get_parent()
	return GoapWorldState.new({
		Facts.CAMP_HAS_WOOD: camp.stock_count(&"wood") > 0,
		Facts.CAMP_HAS_STONE: camp.stock_count(&"stone_item") > 0,
		Facts.HAS_FIRE: camp.has_fire(),
		Facts.FIRE_STABLE: camp.has_stable_fire(),
		Facts.FIRE_LOW: not camp.has_stable_fire(),
		Facts.STOCKPILE_FULL: camp.stockpile_full(),
	})
