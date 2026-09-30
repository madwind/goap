extends GoapCostModel
## Not a scene reference, but still forbidden in a pure simulated state.


static func apply_cost_effect(simulation: Dictionary, _context: Dictionary) -> void:
	simulation.object = RefCounted.new()
