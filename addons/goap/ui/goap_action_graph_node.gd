class_name GoapActionGraphNode
extends GoapBaseGraphNode

var condition_status: Label


func _init(action: GoapAction, world: GoapWorldState) -> void:
	super._init(action.name, GoapTheme.definition_script(action))
	custom_minimum_size.x = 280
	condition_status = Label.new()
	condition_status.text = "Preconditions met" if world.satisfies(
		action.preconditions
	) else "Needs preparation"
	add_child(condition_status)
	add_section("Effects")
	add_facts(action.effects, null, "effects")
	add_section("Preconditions")
	if action.preconditions.size() == 0:
		var label := Label.new()
		label.text = "None"
		add_child(label)
	else:
		add_facts(action.preconditions, world, "requirements")
	set_color(
		GoapTheme.COLOR_SUCCESS if world.satisfies(
			action.preconditions
		) else GoapTheme.COLOR_PENDING
	)
