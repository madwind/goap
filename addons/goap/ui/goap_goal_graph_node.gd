class_name GoapGoalGraphNode
extends GoapBaseGraphNode


func _init(goal: GoapGoal) -> void:
	super._init(goal.name, goal.get_script())
	for key in goal.desired_state.keys():
		add_child(new_state(key, goal.desired_state.get_state(key)))
	set_slot_enabled_right(0, true)
	set_slot_type_right(0, TYPE_BOOL)
	set_color(GoapTheme.COLOR_DISABLED)
