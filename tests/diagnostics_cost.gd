extends GoapCostModel


static func get_cost(_simulation: Dictionary, context: Dictionary) -> float:
	return float(context.get(&"cost", 1.0))
