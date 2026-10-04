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
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 1)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = Vector3(-12, 2, 12)
	ant.global_position = Vector3(-12, 0.1, 14)
	ant.rotation = Vector3.ZERO
	ant.has_food = true
	ant.carried_food.show()
	var highest := 0.0
	var attached := false
	var landed := false
	for frame in range(600):
		await physics_frame
		ant.velocity = Vector3(0, -0.2, -1.6)
		ant.surface_crawler.before_move(ant, 1.0 / 60.0)
		ant.move_and_slide()
		highest = maxf(highest, ant.global_position.y)
		attached = attached or ant.surface_crawler.active
		if attached and not ant.surface_crawler.active and ant.global_position.y > 3.5:
			landed = true
			break
	print("WALL RESULT: attached=", attached, " highest=", highest, " landed=", landed, " pos=", ant.global_position)
	assert(attached and highest > 3.5 and landed)
	assert(ant.has_food)
	var descended := false
	for frame in range(450):
		await physics_frame
		ant.velocity = Vector3(0, -0.2, -1.6)
		ant.surface_crawler.before_move(ant, 1.0 / 60.0)
		ant.move_and_slide()
		if ant.global_position.y < 0.5:
			descended = true
			break
	assert(descended and ant.global_position.y > -0.5)
	assert(not ant.surface_crawler.climbable(world.get_node("NavigationRegion3D/Sphere")))
	wall.add_to_group("glass_surface")
	assert(not ant.surface_crawler.climbable(wall))
	ant.surface_crawler.reset(ant)
	ant.global_position = Vector3(-12, 0.1, 14)
	ant.rotation = Vector3.ZERO
	for frame in range(100):
		await physics_frame
		ant.velocity = Vector3(0, -0.2, -1.6)
		ant.surface_crawler.before_move(ant, 1.0 / 60.0)
		ant.move_and_slide()
	assert(not ant.surface_crawler.active and ant.global_position.y < 0.5)
	print("WALL CRAWLING PASS: solid-wall ascent/top/descent, carried food retained, glass rejected")
	quit(0)
