class_name GoapPlanNode
var parent: GoapPlanNode
var action: GoapAction
var remaining_goals: GoapWorldState
var goal: GoapGoal


static func from_goal(goal: GoapGoal) -> GoapPlanNode:
	var plan_node := GoapPlanNode.new()
	plan_node.remaining_goals = goal.desired_state
	plan_node.goal = goal
	return plan_node


func _to_string() -> String:
	return action.name if action else "null"
