class_name GoapActionGraphNode
extends GoapBaseGraphNode


func _init(action: GoapAction, unsatisfied_state: GoapWorldState) -> void:
	super._init(action.name, action.get_script())
	add_separator("Effects")
	build_input(action.effects)
	var pre_unsatisfied_state := action.preconditions.get_unsatisfied_goals(unsatisfied_state)
	if pre_unsatisfied_state.size() > 0:
		add_separator("Unsatisfied State")
		build_output(pre_unsatisfied_state)
	if action.preconditions.size() > 0:
		add_separator("Preconditions")
		build_output(action.preconditions)


func build_input(state: GoapWorldState) -> void:
	if state.size() > 0:
		for key in state.keys():
			add_child(new_state(key, state.get_state(key)))
			if get_input_port_count() == 0:
				var port := get_child_count() - 1
				set_slot_enabled_left(port, true)
				set_slot_type_left(port, TYPE_BOOL)


func build_output(state: GoapWorldState) -> void:
	if state.size() > 0:
		for key in state.keys():
			add_child(new_state(key, state.get_state(key)))
			if get_output_port_count() == 0:
				var port := get_child_count() - 1
				set_slot_enabled_right(port, true)
				set_slot_type_right(port, TYPE_BOOL)


func add_separator(text: String) -> void:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var left_separator = HSeparator.new()
	left_separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_separator)

	var label = Label.new()
	label.text = text
	hbox.add_child(label)

	var right_separator = HSeparator.new()
	right_separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_separator)

	add_child(hbox)
