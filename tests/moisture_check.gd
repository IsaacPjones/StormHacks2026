extends SceneTree


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	var ecosystem: Node = world.get_node("Ecosystem")
	ecosystem.set_physics_process(false)
	ecosystem.soil_moisture = 95.0
	ecosystem.water()
	assert(ecosystem.soil_moisture == 100.0)
	ecosystem.soil_moisture = 60.0
	var before: float = ecosystem.soil_moisture
	ecosystem._physics_process(60.0)
	assert(ecosystem.soil_moisture < before and ecosystem.soil_moisture > 50.0)
	ecosystem.soil_moisture = 10.0
	assert(ecosystem.production_multiplier() < 1.0 and ecosystem.moisture_warning().contains("dry"))
	ecosystem.soil_moisture = 95.0
	assert(ecosystem.production_multiplier() < 1.0 and ecosystem.moisture_warning().contains("wet"))
	ecosystem.soil_moisture = 60.0
	var plant: Node = get_nodes_in_group("productive_plants")[0]
	plant.set_physics_process(false)
	plant.time_left[0] = 20.0
	plant._physics_process(4.0)
	assert(is_equal_approx(plant.time_left[0], 16.0))
	ecosystem.soil_moisture = 10.0
	plant._physics_process(4.0)
	assert(is_equal_approx(plant.time_left[0], 15.0))
	ecosystem.soil_moisture = 60.0
	ecosystem.set_physics_process(true)
	paused = true
	before = ecosystem.soil_moisture
	var time_before: float = ecosystem.simulation_time
	for _frame in range(10):
		await process_frame
	assert(ecosystem.soil_moisture == before and ecosystem.simulation_time == time_before)
	paused = false
	print("MOISTURE PASS: capped watering, evaporation plus uptake, comfort/warnings, production slowdown, paused timers")
	quit(0)
