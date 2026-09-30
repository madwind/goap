extends GoapWorldStateProvider
## Resource capability adapter. Other kinds of state have their own providers.
## Translate game capabilities into GOAP facts without teaching the planner
## what animals, trees or drops mean.


func get_world_state(agent: GoapAgent) -> GoapWorldState:
	var resource := get_parent()
	var state := GoapWorldState.new()
	if not resource.harvest_method.is_empty() and resource.has_harvest_drops():
		state.set_state(resource.harvest_available_fact(), resource.can_harvest(agent.actor))
	if resource.item != null:
		state.set_state(resource.item.available_fact(), resource.available and not resource.in_transit)
	return state
