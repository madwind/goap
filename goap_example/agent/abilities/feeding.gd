extends RefCounted

const Execution = preload("res://goap_example/agent/abilities/execution.gd")


static func eat_raw_meat(actor: Node3D) -> Execution:
	return Execution.new(actor, "Eat raw meat", _eat.bind(false), _has_food.bind(false))


static func eat_cooked_meat(actor: Node3D) -> Execution:
	return Execution.new(actor, "Eat cooked meat", _eat.bind(true), _has_food.bind(true))


static func drink_water(actor: Node3D) -> Execution:
	return Execution.new(actor, "Drink water", _drink, _has_water)


static func _has_water(execution: Execution) -> Execution.State:
	return Execution.State.RUNNING if execution.actor.water else Execution.State.FAILED


static func _drink(execution: Execution) -> Execution.State:
	if execution.elapsed < 0.8:
		return Execution.State.RUNNING
	execution.actor.drink()
	return Execution.State.SUCCEEDED


static func _has_food(execution: Execution, cooked: bool) -> Execution.State:
	var available: bool = execution.actor.cooked_meat if cooked else execution.actor.raw_meat
	return Execution.State.RUNNING if available else Execution.State.FAILED


static func _eat(execution: Execution, cooked: bool) -> Execution.State:
	if execution.elapsed < 0.8:
		return Execution.State.RUNNING
	execution.actor.eat(cooked)
	return Execution.State.SUCCEEDED
