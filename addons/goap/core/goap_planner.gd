class_name GoapPlanner

var _agent: GoapAgent


func _init(agent: GoapAgent) -> void:
	_agent = agent


func _select_priority_goal() -> GoapGoal:
	var priority_goal: GoapGoal = null
	for goal in _agent.goals:
		if goal.is_valid(_agent.world_state) and (priority_goal == null or goal.get_priority() > priority_goal.get_priority()):
			priority_goal = goal
	return priority_goal


func generate_candidate_plan_nodes() -> Array[GoapPlanNode]:
	var goal := _select_priority_goal()
	var root_plan_node := GoapPlanNode.from_goal(goal)
	var valid_plan_nodes: Array[GoapPlanNode] = []
	var invalid_plan_nodes: Array[GoapPlanNode] = []
	_expand_goal_plan(goal, valid_plan_nodes, invalid_plan_nodes)
	return valid_plan_nodes


func _expand_goal_plan(goal: GoapGoal, valid_plan_nodes: Array[GoapPlanNode], invalid_plan_nodes: Array[GoapPlanNode]) -> void:
	_expand_plan_recursively(GoapPlanNode.from_goal(goal), valid_plan_nodes, invalid_plan_nodes)


func _expand_plan_recursively(current_node: GoapPlanNode, valid_plan_nodes: Array[GoapPlanNode], invalid_plan_nodes: Array[GoapPlanNode]) -> bool:
	var has_valid_branch := false
	var unsatisfied_state := _agent.world_state.get_unsatisfied_goals(current_node.unmet_goals)

	if unsatisfied_state.size() == 0:
		valid_plan_nodes.append(current_node)
		return true

	for action in _agent.actions:
		var effects := action.effects
		if effects.match_first(unsatisfied_state) and (action.is_valid(_agent) or _agent.debug):
			var unmet_goals := effects.get_unsatisfied_goals(unsatisfied_state)
			unmet_goals.merge(action.preconditions)
			var child_node := GoapPlanNode.new()
			child_node.action = action
			child_node.parent = current_node
			child_node.unmet_goals = unmet_goals
			has_valid_branch = true
			if not _expand_plan_recursively(child_node, valid_plan_nodes, invalid_plan_nodes):
				invalid_plan_nodes.append(child_node)

	return has_valid_branch
