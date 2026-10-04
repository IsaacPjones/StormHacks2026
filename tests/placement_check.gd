extends SceneTree

const Catalog = preload("res://scripts/placement_catalog.gd")


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	seed(42)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	for plant in get_nodes_in_group("productive_plants"):
		plant.production_enabled = false
	for creature in get_nodes_in_group("ants") + get_nodes_in_group("isopods"):
		creature.set_physics_process(false)
	var service: Node = world.get_node("SpawnService")
	var placement: Node = world.get_node("FoodPlacement")
	var items := Catalog.items()
	assert(not service.can_place(Vector3(40, 0, 0), items[0]))
	assert(not service.can_place(world.get_node("NavigationRegion3D/Plant").global_position, items[0]))
	var point := Vector3.INF
	for x in range(-20, 21, 4):
		for z in range(-20, 21, 4):
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 4, z), Vector3(x, -2, z), 1)
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and service.can_place(hit.position, items[-1]):
				point = hit.position
				break
		if point.is_finite():
			break
	assert(point.is_finite(), "There must be clear, accessible ground for food")
	placement.begin_placement(items[-1])
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(14, 14)
	placement._unhandled_input(event)
	assert(not placement.spawn_requested, "UI click must not request placement")
	var food: Node3D = service.spawn_item(items[-1], point)
	assert(food != null and food.get_meta("player_placed"))
	assert(not service.can_place(point, items[0]), "Existing food blocks overlapping bug placement")
	var plant_point: Vector3 = service.find_safe_point(world.get_node("Ant").global_position, items[3], 8.0)
	assert(plant_point.is_finite())
	var plant: Node3D = service.spawn_item(items[3], plant_point)
	assert(plant != null)
	for _frame in range(5):
		await physics_frame
	var camera: Camera3D = world.get_node("CameraRig/Camera3D")
	var screen := camera.unproject_position(plant.global_position + Vector3.UP * 0.6)
	placement.remove_at(screen)
	assert(plant.is_queued_for_deletion(), "Player-created plant can be removed")
	assert(is_instance_valid(world.get_node("NavigationRegion3D/Plant")), "Authored tree remains untouched")
	var scraps_item: Resource
	for item in items:
		if item.scene.resource_path == "res://scenes/scraps.tscn":
			scraps_item = item
	var scraps_point: Vector3 = service.find_safe_point(Vector3(-10, 0, 8), scraps_item, 8.0)
	assert(scraps_point.is_finite())
	var scraps: Node3D = service.spawn_item(scraps_item, scraps_point)
	assert(scraps != null)
	await physics_frame
	await physics_frame
	placement.remove_at(camera.unproject_position(scraps.global_position + Vector3.UP * 0.25))
	assert(scraps.is_queued_for_deletion(), "Player-placed detritus can also be removed")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	placement._unhandled_input(escape)
	assert(not placement.active)
	print("PLACEMENT PASS: actual ground, enclosure bounds, obstacle overlap, food access, UI suppression, removal, Escape")
	quit(0)
