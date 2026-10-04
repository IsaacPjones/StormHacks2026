extends SceneTree


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	seed(12)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	var home: AntHome = world.get_node("NavigationRegion3D/Home")
	var ant: CharacterBody3D = world.get_node("Ant")
	for plant in get_nodes_in_group("productive_plants"):
		plant.set("production_enabled", false)
	for creature in get_nodes_in_group("ants") + get_nodes_in_group("isopods"):
		if creature != ant:
			creature.set_physics_process(false)
	var map: RID = world.get_node("NavigationRegion3D").get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, ant.global_position, home.get_arrival_position(), true)
	if path.is_empty() or path[path.size() - 1].distance_to(home.get_arrival_position()) > 0.65:
		push_error("Tunnel navigation does not reach the underground home")
		quit(1)
		return
	ant.has_food = true
	ant.carried_food.show()
	var deposited := false
	var surfaced := false
	var lowest_y := 0.0
	for _frame in range(15000):
		await physics_frame
		lowest_y = minf(lowest_y, ant.global_position.y)
		if home.stored_portions > 0:
			deposited = true
		if deposited and ant.global_position.y > -0.4:
			surfaced = true
			break
	if not deposited or lowest_y > home.global_position.y + 0.6:
		push_error("Ant could not physically descend and deposit underground")
		quit(1)
	elif not surfaced:
		push_error("Ant deposited but could not return to the surface")
		quit(1)
	else:
		print("TUNNEL ROUTE PASS: descended to y=%.2f, deposited underground, returned to surface" % lowest_y)
		quit(0)
