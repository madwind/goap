extends GoapCostModel

static func get_cost(simulation: Dictionary, _context: Dictionary) -> float:
	return 0.2 if simulation.get(&"starving", false) or simulation.get(&"low_health", false) else 35.0
