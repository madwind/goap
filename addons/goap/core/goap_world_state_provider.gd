@abstract
class_name GoapWorldStateProvider
extends Node
## Scene-side observation contract. Attach a concrete provider to a game object.
## Called on the main thread, only for providers discovered by the requesting agent.
## Queries must not change the world, reserve targets, or execute abilities.
## Overrides of _enter_tree() / _exit_tree() must call super to preserve registration.

enum Scope { WORLD, ACTOR }
const WORLD_GROUP := &"goap_world_state_providers"

## ACTOR providers are private to agents whose actor is the provider's parent.
@export var scope: Scope = Scope.WORLD:
	set(value):
		if scope == value:
			return
		if is_inside_tree():
			remove_from_group(_discovery_group())
		scope = value
		if is_inside_tree():
			add_to_group(_discovery_group())

@abstract
func get_world_state(agent: GoapAgent) -> GoapWorldState


func _enter_tree() -> void:
	add_to_group(_discovery_group())


func _exit_tree() -> void:
	remove_from_group(_discovery_group())


func _discovery_group() -> StringName:
	return _actor_group(get_parent()) if scope == Scope.ACTOR else WORLD_GROUP


static func _actor_group(owner: Node) -> StringName:
	return StringName("goap_actor_state:%d" % owner.get_instance_id())


## Optional scene-wide discovery backed by Godot's group index. Script folders
## and game object types do not affect discovery. Sensors may filter this list
## or supply their own list to collect(). ACTOR providers never leak to peers.
static func discover(scene_root: Node, agent: GoapAgent) -> Array[GoapWorldStateProvider]:
	var result: Array[GoapWorldStateProvider] = []
	if not is_instance_valid(scene_root) or not scene_root.is_inside_tree():
		return result
	var candidates := scene_root.get_tree().get_nodes_in_group(WORLD_GROUP)
	if is_instance_valid(agent) and is_instance_valid(agent.actor):
		candidates.append_array(scene_root.get_tree().get_nodes_in_group(_actor_group(agent.actor)))
	for candidate in candidates:
		if candidate is GoapWorldStateProvider and (candidate == scene_root or scene_root.is_ancestor_of(candidate)) and _is_active(candidate):
			result.append(candidate)
	return result


static func _is_active(provider: GoapWorldStateProvider) -> bool:
	if not is_instance_valid(provider) or not provider.is_inside_tree():
		return false
	var node: Node = provider
	while node != null:
		if node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return true


## Availability is existential: one available source is enough, irrespective of
## provider order. Use distinct keys for unrelated facts. ACTOR providers own
## local facts and override world contributions, including explicit false values.
static func collect(providers: Array[GoapWorldStateProvider], agent: GoapAgent) -> GoapWorldState:
	var observed := GoapWorldState.new()
	var local := GoapWorldState.new()
	for provider in providers:
		if not is_instance_valid(provider) or not _is_active(provider):
			continue
		if provider.scope == Scope.ACTOR and (not is_instance_valid(agent) or provider.get_parent() != agent.actor):
			continue
		var contribution := provider.get_world_state(agent)
		if contribution == null:
			continue
		if provider.scope == Scope.ACTOR:
			local.merge(contribution, false)
			continue
		for key in contribution.snapshot():
			observed.set_state(key, observed.get_state(key) or contribution.get_state(key))
	observed.merge(local, false)
	return observed
