extends SceneTree

const Catalog = preload("res://scripts/placement_catalog.gd")


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	seed(11)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	var ecosystem: Node = world.get_node("Ecosystem")
	ecosystem.set_physics_process(false)
	for bug in get_nodes_in_group("ants") + get_nodes_in_group("isopods"):
		bug.set_physics_process(false)
	for plant in get_nodes_in_group("productive_plants"):
		plant.production_enabled = false
	var home: AntHome = world.get_node("NavigationRegion3D/Home")
	var service: Node = world.get_node("SpawnService")
	home.stored_portions = 0
	home.worker_interval_seconds = 1.0
	ecosystem.ant_population_cap = 6
	ecosystem.update_reproduction(2.0)
	assert(get_nodes_in_group("ants").size() == 5 and home.worker_progress == 0.0)
	home.stored_portions = 10
	ecosystem.update_reproduction(2.0)
	assert(get_nodes_in_group("ants").size() == 6 and home.stored_portions == 7)
	assert(get_nodes_in_group("ants")[-1].age_seconds == 0.0)
	ecosystem.update_reproduction(2.0)
	assert(get_nodes_in_group("ants").size() == 6 and home.stored_portions == 7)
	var items := Catalog.items()
	var first: Node3D = get_nodes_in_group("isopods")[0]
	var point: Vector3 = service.find_safe_point(first.global_position, items[1], 6.0)
	assert(point.is_finite())
	var second: Node3D = service.spawn_item(items[1], point)
	assert(second != null)
	second.set_physics_process(false)
	ecosystem.isopod_time_left = 0.0
	ecosystem.update_reproduction(0.0)
	assert(get_nodes_in_group("isopods").size() == 2 and ecosystem.isopod_status.contains("food"))
	first.feeding_reserve = 3.0
	second.feeding_reserve = 3.0
	ecosystem.soil_moisture = 10.0
	ecosystem.update_reproduction(0.0)
	assert(get_nodes_in_group("isopods").size() == 2 and ecosystem.isopod_status.contains("moisture"))
	ecosystem.soil_moisture = 60.0
	ecosystem.isopod_time_left = 10.0
	ecosystem.update_reproduction(0.0)
	assert(get_nodes_in_group("isopods").size() == 2)
	ecosystem.isopod_time_left = 0.0
	ecosystem.update_reproduction(0.0)
	assert(get_nodes_in_group("isopods").size() == 3)
	assert(is_equal_approx(first.feeding_reserve + second.feeding_reserve, 3.0))
	assert(get_nodes_in_group("isopods")[-1].age_seconds == 0.0)
	ecosystem.update_reproduction(0.0)
	assert(get_nodes_in_group("isopods").size() == 3)
	ecosystem.isopod_population_cap = 3
	ecosystem.update_reproduction(0.0)
	assert(ecosystem.isopod_status == "Population cap")
	assert(service.spawn_item(items[1], point) == null)
	print("REPRODUCTION PASS: food gates/costs, moisture, cooldown, shared birth timer, caps, newborn maturity and safe spawns")
	quit(0)
