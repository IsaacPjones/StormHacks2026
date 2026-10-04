extends SceneTree


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	world.get_node("Ecosystem").set_physics_process(false)
	for plant in get_nodes_in_group("productive_plants"):
		plant.production_enabled = false
	for bug in get_nodes_in_group("ants") + get_nodes_in_group("isopods"):
		bug.set_physics_process(false)
	var ant: CharacterBody3D = world.get_node("Ant")
	var home: Node3D = world.get_node("NavigationRegion3D/Home")
	ant.global_position = home.get_arrival_position() + Vector3.UP * 0.1
	for frame in range(15):
		await physics_frame
		ant.velocity = Vector3.DOWN
		ant.move_and_slide()
	ant.navigation_ready = true
	ant.home_target = home
	ant.hunger_time_left = 0.0
	ant.time_without_food = 123.0
	home.stored_portions = 1
	ant.update_home_behavior(0.01)
	assert(ant.is_eating and ant.time_without_food == 0.0 and home.stored_portions == 0)
	var saves: Node = root.get_node("TerrariumSave")
	ant.time_without_food = 42.0
	var state: Dictionary = saves.snapshot(world)
	assert(saves.valid_state(state))
	assert(state.bugs[0].fields.time_without_food == 42.0)
	var old_state: Dictionary = state.duplicate(true)
	for record in old_state.bugs:
		record.fields.erase("starvation_seconds")
		record.fields.erase("time_without_food")
	assert(saves.valid_state(old_state), "Older saves remain usable")
	ant.starvation_seconds = 0.3
	ant.time_without_food = 0.0
	ant.is_eating = false
	ant.set_physics_process(true)
	paused = true
	for frame in range(20):
		await physics_frame
	assert(is_instance_valid(ant) and ant.time_without_food == 0.0)
	paused = false
	Engine.time_scale = 4.0
	for frame in range(8):
		await physics_frame
	assert(not is_instance_valid(ant) and get_nodes_in_group("ants").size() == 4)
	var isopod: Node = get_nodes_in_group("isopods")[0]
	isopod.starvation_seconds = 0.3
	isopod.time_without_food = 0.0
	isopod.set_physics_process(true)
	for frame in range(8):
		await physics_frame
	assert(not is_instance_valid(isopod) and get_nodes_in_group("isopods").is_empty())
	Engine.time_scale = 1.0
	world.get_node("ColonyHUD").refresh_display()
	assert(world.get_node("ColonyHUD").ant_count.text == "Ants: 4")
	assert(world.get_node("ColonyHUD").isopod_count.text == "Isopods: 0")
	print("STARVATION PASS: nest meal resets, timers saved, older slots accepted, pause freezes, 4x deaths, live counts")
	quit(0)
