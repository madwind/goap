class_name GoapCostModel
extends RefCounted
## Planning-only code. Implement static methods using simulation/context values.
## Never access Nodes, autoloads, live Resources or mutable static variables.


static func get_cost(_simulation: Dictionary, _context: Dictionary) -> float:
	return 1.0


static func apply_cost_effect(_simulation: Dictionary, _context: Dictionary) -> void:
	pass
