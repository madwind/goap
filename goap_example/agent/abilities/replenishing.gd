extends "res://goap_example/agent/abilities/execution.gd"
## A GOAP-owned delivery composes the same harvest, pickup and stow abilities.
## Cancellation cancels the current operation and leaves carried goods intact.

const Harvesting = preload("res://goap_example/agent/abilities/harvesting.gd")
const Storage = preload("res://goap_example/agent/abilities/storage.gd")
const Execution = preload("res://goap_example/agent/abilities/execution.gd")
var item: Resource
var _operation: Execution
var _depositing := false


func _init(owner: Node3D, definition: Resource) -> void:
	super(owner, "Deliver " + definition.title, Callable(), Callable())
	item = definition


func start() -> void:
	_select_operation()


func advance(delta: float) -> void:
	if state != State.RUNNING:
		return
	if not is_instance_valid(actor) or actor.dead or _operation == null:
		_finish(State.FAILED)
		return
	_operation.advance(delta)
	target = _operation.target
	label = _operation.label
	actor.activity = label
	if _operation.state == State.SUCCEEDED:
		if _depositing:
			_finish(State.SUCCEEDED)
		else:
			_select_operation()
	elif _operation.state != State.RUNNING:
		_finish(State.FAILED)


func cancel() -> void:
	if _operation != null:
		_operation.cancel()
	super.cancel()


func _select_operation() -> void:
	_depositing = actor.has_item(item.inventory_key)
	if _depositing:
		_operation = Storage.stow(actor, actor.get_camp())
	elif not actor.can_carry_item():
		_finish(State.FAILED)
		return
	else:
		var signature: String = item.signature()
		var loose_filter := func(candidate: Node3D) -> bool:
			return candidate.item != null and candidate.item.signature() == signature and not candidate.stored_at_camp
		var loose: Node3D = actor.find_matching_resource(item.kind, loose_filter)
		if loose != null:
			_operation = Harvesting.pick_up(actor, item, loose, true, loose_filter)
		else:
			var source: Node3D = find_source(actor, item)
			if source == null:
				_finish(State.FAILED)
				return
			_operation = Harvesting.harvest(actor, source, source.kind, source.harvest_profile(), true)
	_operation.start()
	target = _operation.target
	label = _operation.label


static func find_source(owner: Node3D, definition: Resource) -> Node3D:
	var chosen: Node3D
	var best := INF
	for candidate in owner.get_parent().resources:
		if not candidate.can_harvest(owner):
			continue
		if not candidate.drops.any(func(drop: Resource) -> bool: return drop != null and drop.signature() == definition.signature()):
			continue
		var distance: float = owner.global_position.distance_squared_to(candidate.global_position)
		if distance < best:
			best = distance
			chosen = candidate
	return chosen
