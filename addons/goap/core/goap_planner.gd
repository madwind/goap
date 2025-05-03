class_name GoapPlanner

var _agent: GoapAgent


func _init(agent: GoapAgent) -> void:
	_agent = agent


func select_best_goal() -> GoapGoal:
	var priority_goal: GoapGoal = null

	for goal in _agent.goals:
		if goal.is_valid(_agent.world_state) and (priority_goal == null or goal.get_priority() > priority_goal.get_priority()):
			priority_goal = goal
	return priority_goal


func get_best_plan() -> GoapPlan:
	var goal := select_best_goal()
	var root_plan_node := GoapPlanNode.from_goal(goal)
	var valid_plan_nodes: Array[GoapPlanNode] = []
	var invalid_plan_nodes: Array[GoapPlanNode] = []
	get_plan_from_goal(goal, valid_plan_nodes, invalid_plan_nodes)
	var best_plan: GoapPlan
	for p in valid_plan_nodes:
		var plan = GoapPlan.new(p, _agent)
		if not best_plan or plan.cost < best_plan.cost:
			best_plan = plan
	return best_plan


func get_plan_from_goal(goal: GoapGoal, valid_plan_nodes: Array[GoapPlanNode], invalid_plan_nodes: Array[GoapPlanNode]) -> void:
	_build_plan(GoapPlanNode.from_goal(goal), valid_plan_nodes, invalid_plan_nodes)


func _build_plan(plan_node: GoapPlanNode, valid_plan_nodes: Array[GoapPlanNode], invalid_plan_nodes: Array[GoapPlanNode]) -> bool:
	var has_followup := false
	var unsatisfied_state := _agent.world_state.get_unsatisfied_goals(plan_node.remaining_goals)

	if unsatisfied_state.size() == 0:
		valid_plan_nodes.append(plan_node)
		return true

	for action in _agent.actions:
		var effects := action.effects
		if effects.match_first(unsatisfied_state) and (action.is_valid(_agent) or _agent.debug):
			var remaining_goals := effects.get_unsatisfied_goals(unsatisfied_state)
			remaining_goals.merge(action.preconditions)
			var sub_plan_node := GoapPlanNode.new()
			sub_plan_node.action = action
			sub_plan_node.parent = plan_node
			sub_plan_node.remaining_goals = remaining_goals
			has_followup = true
			if not _build_plan(sub_plan_node, valid_plan_nodes, invalid_plan_nodes):
				invalid_plan_nodes.append(sub_plan_node)

	return has_followup
