class_name GoapUnsatisfiedStateGraphNode
extends GoapBaseGraphNode


func _init(unsatisfied_state: GoapWorldState) -> void:
	super._init("UnsatisfiedState")
	for key in unsatisfied_state.keys():
		add_child(new_state(key, unsatisfied_state.get_state(key)))
	set_slot_enabled_left(0, true)
	set_slot_type_left(0, TYPE_BOOL)
	set_color(GoapTheme.COLOR_FAILED)
