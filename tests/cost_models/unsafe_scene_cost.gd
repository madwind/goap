extends GoapCostModel
## Intentionally unsafe: diagnostics must reject this fixture before executing it.


static func get_cost(_simulation: Dictionary, _context: Dictionary) -> float:
	return float((Engine.get_main_loop() as SceneTree).root.get_child_count())
