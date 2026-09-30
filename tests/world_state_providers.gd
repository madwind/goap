extends SceneTree

var checks := 0
var failures := 0


class Provider extends GoapWorldStateProvider:
	var available := true
	var permitted_agent: GoapAgent
	var queries := 0

	func get_world_state(agent: GoapAgent) -> GoapWorldState:
		queries += 1
		return GoapWorldState.new({&"huntable": available and (permitted_agent == null or permitted_agent == agent)})


class Observer extends GoapAgent:
	var discovered: Array[GoapWorldStateProvider] = []
	var hungry := true
	var fact_seen_during_processing := false

	func _process_goap(delta: float) -> void:
		fact_seen_during_processing = world_state.get_state(&"huntable")
		super._process_goap(delta)

	func _observe_world_state() -> GoapWorldState:
		var observed := GoapWorldStateProvider.collect(discovered, self)
		observed.set_state(&"hungry", hungry)
		return observed


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PROVIDER FAIL: " + message)


func run() -> void:
	check_discovery()
	var first := Observer.new()
	var second := Observer.new()
	root.add_child(first)
	root.add_child(second)
	first.set_physics_process(false)
	second.set_physics_process(false)
	var animal := Node.new()
	var live := Provider.new()
	animal.add_child(live)
	root.add_child(animal)
	var depleted := Provider.new()
	depleted.available = false
	root.add_child(depleted)
	first.discovered.assign([live, depleted])
	first._physics_process(0.0)
	check(first.world_state.get_state(&"huntable"), "an unavailable provider cannot hide another available animal")
	check(first.fact_seen_during_processing, "first planning tick reads provider facts before processing")
	check(first.world_state.get_state(&"hungry"), "local actor state is included")
	var captured := first.world_state.snapshot()
	var generation := first.planning_generation
	first.discovered.reverse()
	first.refresh_world_state()
	check(first.planning_generation == generation, "provider order and unchanged observations do not request replanning")
	live.permitted_agent = first
	second.discovered.assign([live])
	second.refresh_world_state()
	check(not second.world_state.get_state(&"huntable"), "capability queries receive the observing agent")
	live.available = false
	first.hungry = false
	var observed_changes: Array[Dictionary] = []
	first.world_state.state_changed.connect(func() -> void: observed_changes.append(first.world_state.to_dictionary()))
	first.refresh_world_state()
	check(first.planning_generation == generation + 1, "one complete observation requests one replan")
	check(observed_changes.size() == 1 and not observed_changes[0].huntable and not observed_changes[0].hungry, "listeners see a complete atomic observation")
	check(captured.huntable and captured.hungry and captured.is_read_only(), "old planning snapshots remain immutable and unchanged")
	live.available = true
	first.refresh_world_state()
	check(first.world_state.get_state(&"huntable"), "regrowth restores availability")
	first.discovered.clear()
	first.refresh_world_state()
	check(not first.world_state.get_state(&"huntable") and not first.world_state.has_state(&"huntable"), "leaving perception clears stale facts")
	first.discovered.assign([live])
	first.refresh_world_state()
	animal.queue_free()
	var before := live.queries
	first.refresh_world_state()
	check(not first.world_state.get_state(&"huntable") and live.queries == before, "queued parent deletion excludes its provider before the next frame")
	await process_frame
	first.refresh_world_state()
	check(not first.world_state.get_state(&"huntable"), "a freed provider in a cached sensor result is skipped safely")
	first.discovered.assign([depleted])
	depleted.available = true
	first._physics_process(0.0)
	check(first.world_state.get_state(&"huntable"), "normal agent physics publishes observations")
	first.suspend()
	depleted.available = false
	first._physics_process(0.0)
	check(first.world_state.get_state(&"huntable"), "suspended agents do not poll providers")
	first.refresh_world_state()
	check(not first.world_state.get_state(&"huntable"), "explicit game events can refresh a suspended agent")
	var legacy := GoapAgent.new()
	legacy.init_goap()
	legacy.world_state.set_state(&"manual", true)
	legacy.refresh_world_state()
	check(legacy.world_state.get_state(&"manual"), "the default null observation preserves manually managed state")
	first.resume()
	depleted.available = true
	first._physics_process(0.0)
	check(first.world_state.get_state(&"huntable"), "resumed agents keep observing providers")
	root.remove_child(depleted)
	first.refresh_world_state()
	check(not first.world_state.get_state(&"huntable"), "detached providers no longer contribute")
	var state := GoapWorldState.new({&"old": true})
	state.replace(GoapWorldState.new())
	check(state.size() == 0, "an empty full observation removes every old fact")
	check(GoapPlanner.is_pure_data(first.world_state.snapshot()), "published planning data contains no scene objects")
	legacy.free()
	first.free()
	second.free()
	depleted.free()
	await process_frame
	print("World state providers: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _initialize() -> void:
	run.call_deferred()


func check_discovery() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var actor_a := Node.new()
	var actor_b := Node.new()
	scene.add_child(actor_a)
	scene.add_child(actor_b)
	var a := GoapAgent.new()
	var b := GoapAgent.new()
	actor_a.add_child(a)
	actor_b.add_child(b)
	a.set_physics_process(false)
	b.set_physics_process(false)
	var nested_object := Node.new()
	scene.add_child(nested_object)
	var public_state := Provider.new()
	nested_object.add_child(public_state)
	var own_a := Provider.new()
	own_a.scope = GoapWorldStateProvider.Scope.ACTOR
	own_a.available = false
	actor_a.add_child(own_a)
	var own_b := Provider.new()
	own_b.scope = GoapWorldStateProvider.Scope.ACTOR
	actor_b.add_child(own_b)
	var unrelated := Provider.new()
	root.add_child(unrelated)
	var found := GoapWorldStateProvider.discover(scene, a)
	check(found.has(public_state) and found.has(own_a) and found.size() == 2, "group discovery includes nested ordinary nodes and the actor's private provider")
	check(not found.has(own_b) and not found.has(unrelated), "discovery excludes another actor and another scene")
	check(not GoapWorldStateProvider.collect(found, a).get_state(&"huntable"), "private false facts override public true facts")
	found.reverse()
	check(not GoapWorldStateProvider.collect(found, a).get_state(&"huntable"), "private ownership is independent of discovery order")
	check(GoapWorldStateProvider.collect(GoapWorldStateProvider.discover(scene, b), b).get_state(&"huntable"), "each actor gets its own private state")
	check(GoapWorldStateProvider.collect([own_b], a).size() == 0, "collect also rejects another actor's private state in a custom sensor list")
	own_b.scope = GoapWorldStateProvider.Scope.WORLD
	check(GoapWorldStateProvider.discover(scene, a).has(own_b), "changing scope updates discovery registration")
	own_b.scope = GoapWorldStateProvider.Scope.ACTOR
	own_a.reparent(actor_b)
	check(not GoapWorldStateProvider.discover(scene, a).has(own_a) and GoapWorldStateProvider.discover(scene, b).has(own_a), "reparenting updates private provider ownership")
	own_a.reparent(actor_a)
	nested_object.remove_child(public_state)
	check(not GoapWorldStateProvider.discover(scene, a).has(public_state), "leaving the tree unregisters a provider")
	nested_object.add_child(public_state)
	check(GoapWorldStateProvider.discover(scene, a).has(public_state), "reentering the tree registers the provider again")
	nested_object.queue_free()
	check(not GoapWorldStateProvider.discover(scene, a).has(public_state), "queued ancestor deletion excludes discovered providers immediately")
	scene.free()
	unrelated.free()
