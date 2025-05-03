class_name GoapPlan
var plan_node: GoapPlanNode
var actions: Array[GoapAction] = []
var cost := 0.0
var step := 0

signal action_succeed(action: GoapAction, completed: bool)


func _init(plan_node: GoapPlanNode, agent: GoapAgent) -> void:
	self.plan_node = plan_node
	_build_action_sequence(plan_node, self)
	_calculate_total_cost(agent, self)


func execute(agent: GoapAgent, delta: float) -> bool:
	if step == actions.size():
		return true

	if actions[step].perform(agent, delta):
		var completed = step == actions.size() - 1
		action_succeed.emit(actions[step], completed)
		agent.world_state.merge(actions[step].effects, completed)
		step += 1
	return false


func _build_action_sequence(plan_node: GoapPlanNode, plan: GoapPlan) -> void:
	if plan_node.goal:
		return
	if plan_node.action:
		plan.actions.push_back(plan_node.action)
	if plan_node.parent:
		_build_action_sequence(plan_node.parent, plan)


func _calculate_total_cost(agent: GoapAgent, plan: GoapPlan) -> void:
	var state := agent.world_state.duplicate()
	for action in plan.actions:
		plan.cost += action.get_cost(agent, state)
		state.merge(action.effects)


func _to_string() -> String:
	return "%s cost:%s" % [actions, cost]
