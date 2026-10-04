extends SceneTree

const Catalog = preload("res://scripts/placement_catalog.gd")


func _initialize() -> void:
	call_deferred("run_check")


func total_food(world: Node3D) -> int:
	var total := 0
	for home in get_nodes_in_group("ant_homes"):
		total += home.stored_portions
	for ant in get_nodes_in_group("ants"):
		total += int(ant.has_food)
	for resource in get_nodes_in_group("food_sources"):
		total += resource.portions
	return total


func run_check() -> void:
	seed(20)
	var saves: Node = root.get_node("TerrariumSave")
	saves.save_path = "res://tests/_save_slot_check.json"
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	for bug in get_nodes_in_group("ants") + get_nodes_in_group("isopods"):
		bug.set_physics_process(false)
	for plant in get_nodes_in_group("productive_plants"):
		plant.production_enabled = false
	world.get_node("Ecosystem").set_physics_process(false)
	var home: AntHome = world.get_node("NavigationRegion3D/Home")
	home.stored_portions = 7
	home.worker_progress = 41.5
	var ants := get_nodes_in_group("ants")
	ants[0].has_food = true
	ants[0].time_without_food = 21.25
	ants[0].carried_food.show()
	ants[1].is_eating = true
	ants[1].eat_time_left = 1.25
	ants[2].surface_crawler.active = true
	ants[2].surface_crawler.normal = Vector3.RIGHT
	ants[2].surface_crawler.elapsed = 3.0
	ants[2].surface_crawler.descending = true
	ants[2].global_basis = ants[2].surface_crawler.aligned_basis(Vector3.DOWN, Vector3.RIGHT, Vector3.ONE)
	ants[2].up_direction = Vector3.RIGHT
	var ecosystem: Node = world.get_node("Ecosystem")
	ecosystem.soil_moisture = 63.5
	ecosystem.simulation_time = 85.25
	ecosystem.isopod_time_left = 34.0
	ecosystem.milestone_progress = 17.5
	get_nodes_in_group("isopods")[0].feeding_reserve = 3.75
	get_nodes_in_group("isopods")[0].time_without_food = 37.5
	get_nodes_in_group("isopods")[0].breeding_cooldown = 13.5
	var service: Node = world.get_node("SpawnService")
	var items := Catalog.items()
	var plant_point: Vector3 = service.find_safe_point(Vector3(-8, 0, 6), items[3], 8)
	assert(plant_point.is_finite())
	var plant: Node3D = service.spawn_item(items[3], plant_point)
	assert(plant != null)
	plant.production_enabled = false
	plant.time_left[0] = 23.25
	for _frame in range(5):
		await physics_frame
	var drop: Node3D = plant.produce_resource(0)
	assert(drop != null)
	drop.consume(1.0)
	var scraps: Node3D = load("res://scenes/scraps.tscn").instantiate()
	scraps.amount = 2.5
	world.add_child(scraps)
	scraps.global_position = Vector3(-12, 0, 6)
	var orange_point: Vector3 = service.find_safe_point(Vector3(-18, 0, 4), items[-1], 8)
	assert(orange_point.is_finite())
	var orange: Node3D = service.spawn_item(items[-1], orange_point)
	assert(orange != null)
	orange.portions = 3
	for _frame in range(5):
		await physics_frame
	paused = true
	var food_before := total_food(world)
	assert(saves.save_world(world), saves.last_error)
	assert(saves.save_world(world), "Second save must atomically replace the first")
	assert(saves.has_valid_save())
	var state: Dictionary = saves.read_save()
	assert(state.plants.size() == 4 and state.resources.size() == 3)
	var invalid: Dictionary = state.duplicate(true)
	invalid.bugs[0].position = ["bad", 0, 0]
	assert(not saves.valid_state(invalid))
	invalid = state.duplicate(true)
	invalid.plants[0].time_left = ["bad"]
	assert(not saves.valid_state(invalid))
	world.queue_free()
	await process_frame
	paused = false
	saves.pending_load = state
	var loaded: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(loaded)
	await loaded.colony_ready
	paused = true
	assert(total_food(loaded) == food_before, "Stored + carried + remaining food must be conserved")
	assert(get_nodes_in_group("ants").size() == 5 and get_nodes_in_group("isopods").size() == 1)
	assert(get_nodes_in_group("productive_plants").size() == 4)
	assert(get_nodes_in_group("resource_sources").size() == 3)
	assert(is_equal_approx(loaded.get_node("Ecosystem").soil_moisture, 63.5))
	assert(is_equal_approx(loaded.get_node("Ecosystem").simulation_time, 85.25))
	assert(is_equal_approx(loaded.get_node("Ecosystem").milestone_progress, 17.5))
	assert(is_equal_approx(loaded.get_node("NavigationRegion3D/Home").worker_progress, 41.5))
	assert(get_nodes_in_group("ants")[0].has_food and get_nodes_in_group("ants")[0].carried_food.visible)
	assert(is_equal_approx(get_nodes_in_group("ants")[0].time_without_food, 21.25))
	assert(is_equal_approx(get_nodes_in_group("isopods")[0].time_without_food, 37.5))
	assert(get_nodes_in_group("ants")[1].is_eating and is_equal_approx(get_nodes_in_group("ants")[1].eat_time_left, 1.25))
	assert(get_nodes_in_group("ants")[2].surface_crawler.active and get_nodes_in_group("ants")[2].up_direction == Vector3.RIGHT)
	assert(get_nodes_in_group("ants")[2].surface_crawler.descending and is_equal_approx(get_nodes_in_group("ants")[2].surface_crawler.elapsed, 3.0))
	assert(is_equal_approx(get_nodes_in_group("isopods")[0].feeding_reserve, 3.75))
	assert(is_equal_approx(get_nodes_in_group("isopods")[0].breeding_cooldown, 13.5))
	var dynamic_plant: Node
	for candidate in get_nodes_in_group("productive_plants"):
		if candidate.get_meta("player_placed", false):
			dynamic_plant = candidate
	assert(dynamic_plant != null and dynamic_plant.active_drops.size() == 1)
	assert(is_equal_approx(dynamic_plant.time_left[0], 23.25))
	assert(is_instance_valid(loaded.get_node("Surface")) and is_instance_valid(loaded.get_node("vine3")), "Authored terrain and decorative vines remain")
	loaded.get_node("Ecosystem").set_physics_process(false)
	for bug in get_nodes_in_group("ants") + get_nodes_in_group("isopods"):
		bug.set_physics_process(false)
	var carrier: Node = get_nodes_in_group("ants")[0]
	carrier.set_physics_process(true)
	paused = false
	for _frame in range(6000):
		await physics_frame
		if not carrier.has_food:
			break
	assert(not carrier.has_food and loaded.get_node("NavigationRegion3D/Home").stored_portions == 8, "Reloaded carrier must deliver exactly one portion")
	assert(total_food(loaded) == food_before)
	var corrupt := FileAccess.open(saves.save_path, FileAccess.WRITE)
	corrupt.store_string("{invalid json")
	corrupt.close()
	assert(not saves.has_valid_save())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.save_path))
	assert(not saves.has_valid_save())
	paused = false
	print("SAVE SLOT PASS: overwrite, invalid/missing handling, quantities, carried/eaten food, plants/drop caps, moisture/time, reproduction, authored map, rebuilt navigation")
	quit(0)
