class_name GoapGoalGraphNode
extends GoapBaseGraphNode


func _init(goal: GoapGoal, world: GoapWorldState) -> void:
	super._init(goal.name, GoapTheme.definition_script(goal))
	custom_minimum_size.x = 280
	var status := Label.new()
	status.text = "Goal reached" if world.satisfies(goal.goal_state) else "Goal"
	add_child(status)
	add_section("Desired state")
	if goal.goal_state.size() == 0:
		var label := Label.new()
		label.text = "No conditions"
		add_child(label)
	else:
		add_facts(goal.goal_state, world, "requirements")
	set_color(
		GoapTheme.COLOR_SUCCESS if world.satisfies(goal.goal_state) else GoapTheme.COLOR_ACTIVE
	)
