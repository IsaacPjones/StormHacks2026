extends SceneTree


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	var ecosystem: Node = world.get_node("Ecosystem")
	ecosystem.set_physics_process(false)
	ecosystem.milestone_ant_target = 5
	ecosystem.milestone_isopod_target = 1
	ecosystem.milestone_duration_seconds = 2.0
	ecosystem.update_milestone(1.0)
	assert(ecosystem.milestone_progress == 0.0)
	world.get_node("NavigationRegion3D/Home").stored_portions = 8
	get_nodes_in_group("isopods")[0].feeding_reserve = 2.0
	ecosystem.update_milestone(1.0)
	assert(ecosystem.milestone_progress == 1.0 and not ecosystem.milestone_complete)
	ecosystem.soil_moisture = 10.0
	ecosystem.update_milestone(1.0)
	assert(ecosystem.milestone_progress == 0.0)
	ecosystem.soil_moisture = 60.0
	ecosystem.update_milestone(2.0)
	assert(ecosystem.milestone_complete and ecosystem.milestone_progress == 2.0)
	ecosystem.update_milestone(10.0)
	assert(ecosystem.milestone_complete and ecosystem.milestone_progress == 2.0)
	print("MILESTONE PASS: adequate food/moisture, continuous support, configurable targets, one success, continued play")
	quit(0)
