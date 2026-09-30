extends GoapCostModel


static func get_cost(simulation: Dictionary, context: Dictionary) -> float:
	if context.get(
		"require_worker",
		false
	) and OS.get_thread_caller_id() == OS.get_main_thread_id():
		return -1.0
	var delay_usec: int = context.get("delay_usec", 0)
	if delay_usec > 0:
		OS.delay_usec(delay_usec)
	return float(simulation.get("position", 0.0)) if context.get("uses_position", false) else float(
		context.get("price", 1.0)
	)


static func apply_cost_effect(simulation: Dictionary, context: Dictionary) -> void:
	if context.get("require_worker", false):
		assert(
			OS.get_thread_caller_id() != OS.get_main_thread_id(),
			"cost effects must execute on worker"
		)
	var position: float = context.get("position_after", -1.0)
	if position >= 0:
		simulation.position = position
