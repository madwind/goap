extends "res://goap_example/agent/goap/ability_action.gd"
## One immutable definition per observed resource profile, with runtime target selection.

var profile: String
var kind: StringName
var available_fact: StringName
var available_label: String
var method_label: String
var full_label: String
var display_name: String


func configure(resource: Node3D) -> void:
	profile = resource.harvest_profile()
	kind = resource.kind
	cost = float(resource.max_health())
	effects = GoapWorldState.new()
	var products := PackedStringArray()
	var signatures := PackedStringArray()
	for item in resource.drops:
		if item == null:
			continue
		effects.set_state(item.available_fact(), true)
		products.append(String(item.kind).uri_encode())
		signatures.append(item.signature())
	products.sort()
	signatures.sort()
	var source := String(kind).uri_encode()
	var method := String(resource.harvest_method).uri_encode()
	available_label = "Can %s %s (drops: %s)" % [method, source, "+".join(products)]
	method_label = available_label
	full_label = "Can %s %s (drops: %s)" % [method, source, "+".join(signatures)]
	# Identity always keeps all fields; discovering a variant never renames a live key.
	available_fact = resource.harvest_available_fact()
	preconditions = GoapWorldState.new({available_fact: true})
	display_name = "%s %s" % [String(resource.harvest_method).capitalize(), String(kind).capitalize()]
	name = StringName(display_name)


func get_id() -> String:
	return "Harvest:" + profile


func start(agent: GoapAgent) -> void:
	execution = agent.actor.harvest(null, kind, profile, agent.is_resource_observed)
