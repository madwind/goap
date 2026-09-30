extends "res://goap_example/agent/goap/ability_action.gd"

const Facts = preload("res://goap_example/survival/fact_keys.gd")
const Replenishing = preload("res://goap_example/agent/abilities/replenishing.gd")
var item: Resource


func configure(definition: Resource) -> void:
	item = definition.duplicate()
	name = StringName("Deliver " + item.title)
	preconditions = GoapWorldState.new({Facts.STOCKPILE_FULL: false})
	# Boolean stock goals repeat one delivery until the observed counts are full.
	effects = GoapWorldState.new({Facts.STOCKPILE_FULL: true})


func get_id() -> String:
	return "Replenish:" + item.signature()


func is_valid(agent: GoapAgent) -> bool:
	if agent == null:
		return true
	var actor: Node3D = agent.actor
	if actor.dead:
		return false
	# The final deposit changes stock before GOAP polls the completed operation.
	# A successful delivery must still be reported as success at the stock limit.
	if execution != null and execution.state == Replenishing.State.SUCCEEDED:
		return true
	if actor.get_camp().stock_count(item.kind) >= actor.get_camp().STOCK_LIMIT:
		return false
	if actor.has_item(item.inventory_key):
		return true
	if not actor.can_carry_item():
		return false
	var loose: Node3D = actor.find_matching_resource(item.kind, func(candidate: Node3D) -> bool:
		return candidate.item != null and candidate.item.signature() == item.signature() and not candidate.stored_at_camp
	)
	return loose != null or Replenishing.find_source(actor, item) != null


func start(agent: GoapAgent) -> void:
	execution = agent.actor._begin_ability(Replenishing.new(agent.actor, item))
