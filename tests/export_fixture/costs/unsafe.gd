extends GoapCostModel


static func get_cost(_simulation: Dictionary, _context: Dictionary) -> float:
	return float(Engine.get_main_loop().root.get_child_count())
