extends Node3D

const ANT_SCENE: PackedScene = preload("res://scenes/ant.tscn")

@export_range(1, 20, 1) var starting_ant_count: int = 5
@export var exploration_limit: float = 24.0
@export var enclosure_radius: float = 28.0
## Optional editable CSG terrain. Its carved result supplies physical/nav geometry.
@export_node_path("CSGShape3D") var terrain_csg_path: NodePath

signal colony_ready

var map_ready: bool = false

var food_obstacles: Dictionary = {}
var obstacle_check_left: float = 0.0


func _ready() -> void:
	add_to_group("terrariums")
	var glass := get_node_or_null("NavigationRegion3D/Sphere")
	if glass != null:
		glass.add_to_group("glass_surface")
	var surface := get_node_or_null("Surface/Terrain3D")
	if surface != null:
		surface.add_to_group("placement_ground")
	prepare_navigation.call_deferred()


func prepare_navigation() -> void:
	var region: NavigationRegion3D = $NavigationRegion3D
	if not terrain_csg_path.is_empty():
		for creature in get_tree().get_nodes_in_group("ants") + get_tree().get_nodes_in_group("isopods"):
			creature.set_physics_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var terrain: CSGShape3D = get_node(terrain_csg_path)
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		body.add_to_group("placement_ground")
		var shape := CollisionShape3D.new()
		shape.shape = terrain.bake_collision_shape()
		terrain.use_collision = false
		body.add_child(shape)
		region.add_child(body)
		body.global_transform = terrain.global_transform
		await get_tree().process_frame
		await get_tree().physics_frame
		NavigationServer3D.map_set_cell_size(region.get_navigation_map(), region.navigation_mesh.cell_size)
		NavigationServer3D.map_set_cell_height(region.get_navigation_map(), region.navigation_mesh.cell_height)
		# Keep the nest on the chamber floor rather than floating above it.
		for home in get_tree().get_nodes_in_group("ant_homes"):
			var query := PhysicsRayQueryParameters3D.create(home.global_position + Vector3.UP * 0.5, home.global_position + Vector3.DOWN * 5.0, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.collider.is_in_group("placement_ground"):
				home.global_position.y = hit.position.y
	# Bake only the static enclosure. Player-dropped food must not leave fixed
	# holes in the navigation mesh after it moves.
	bake_navigation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(region.get_navigation_map())
	# Allow the existing navigation region to synchronize before placing ants.
	await initialize_colony()
	var saves := get_node_or_null("/root/TerrariumSave")
	if saves != null and not saves.pending_load.is_empty():
		saves.apply_state(self, saves.pending_load)
		saves.pending_load = {}
		await get_tree().physics_frame
		await get_tree().physics_frame
		food_obstacles.clear()
		for food in get_tree().get_nodes_in_group("food_sources"):
			if food is RigidBody3D and food.sleeping:
				food_obstacles[food.get_instance_id()] = food.global_position
		update_food_navigation()
		await get_tree().physics_frame
		await get_tree().physics_frame
		NavigationServer3D.map_force_update(region.get_navigation_map())
	map_ready = true
	for creature in get_tree().get_nodes_in_group("ants") + get_tree().get_nodes_in_group("isopods"):
		creature.set_physics_process(true)
	if saves != null and saves.pending_new:
		saves.pending_new = false
		if not saves.save_world(self):
			$ColonyHUD.show_notice(saves.last_error)
	$ColonyHUD.refresh_display()
	colony_ready.emit()


func _physics_process(delta: float) -> void:
	if not map_ready:
		return
	obstacle_check_left -= delta
	if obstacle_check_left > 0.0:
		return
	obstacle_check_left = 0.5
	var settled: Dictionary = {}
	var changed: bool = false
	for food in get_tree().get_nodes_in_group("food_sources"):
		var body := food as RigidBody3D
		if not is_instance_valid(body) or not body.sleeping:
			continue
		var key: int = body.get_instance_id()
		settled[key] = body.global_position
		if not food_obstacles.has(key) or food_obstacles[key].distance_to(body.global_position) > 0.25:
			changed = true
	if settled.size() != food_obstacles.size():
		changed = true
	if changed:
		food_obstacles = settled
		update_food_navigation()


func update_food_navigation() -> void:
	# Baking parses static bodies. Temporary copies of sleeping food supply
	# obstacle geometry without freezing the real physics items.
	var region: NavigationRegion3D = $NavigationRegion3D
	var proxies: Array[StaticBody3D] = []
	for food in get_tree().get_nodes_in_group("food_sources"):
		if not food_obstacles.has(food.get_instance_id()):
			continue
		var collider: CollisionShape3D = food.get_node("CollisionShape3D")
		var proxy := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = collider.shape
		proxy.add_child(shape)
		region.add_child(proxy)
		proxy.global_transform = collider.global_transform
		proxies.append(proxy)
	bake_navigation()
	for proxy in proxies:
		region.remove_child(proxy)
		proxy.queue_free()


func initialize_colony() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var home: Node3D = $NavigationRegion3D/Home
	var map: RID = $NavigationRegion3D.get_navigation_map()
	while NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame

	var existing_ants: Array[Node] = get_tree().get_nodes_in_group("ants")
	for ant in existing_ants:
		ant.set("wander_limit", exploration_limit)
	for bug in get_tree().get_nodes_in_group("isopods"):
		bug.set("wander_limit", exploration_limit)

	for index in range(existing_ants.size(), starting_ant_count):
		var ant: CharacterBody3D = ANT_SCENE.instantiate()
		ant.set("wander_limit", exploration_limit)
		var angle: float = TAU * float(index) / float(starting_ant_count)
		var origin: Vector3 = existing_ants[0].global_position if not existing_ants.is_empty() else home.global_position
		var spawn_point: Vector3 = origin + Vector3(cos(angle), 0, sin(angle)) * 1.8
		spawn_point = NavigationServer3D.map_get_closest_point(map, spawn_point)
		add_child(ant)
		ant.global_position = spawn_point + Vector3(0, 0.1, 0)


func get_food_placement_surface(point: Vector3, clearance: float) -> Dictionary:
	# Sample the whole footprint so food cannot be dropped across a tunnel mouth.
	var center: Dictionary = {}
	for index in range(9):
		var offset := Vector3.ZERO if index == 0 else Vector3(cos(TAU * (index - 1) / 8.0), 0.0, sin(TAU * (index - 1) / 8.0)) * clearance
		var sample_point := point + offset
		var query := PhysicsRayQueryParameters3D.create(sample_point + Vector3.UP * 0.25, sample_point + Vector3.DOWN * 0.3, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider.is_in_group("placement_ground") or hit.normal.y < 0.97 or absf(hit.position.y - point.y) > 0.1:
			return {}
		if index == 0:
			center = hit
	return center


func bake_navigation() -> void:
	var region: NavigationRegion3D = $NavigationRegion3D
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(region.navigation_mesh, source, region)
	# Reuse the installed Terrain3D's own nav source generation. Never change its
	# painted terrain, textures, holes, or transform to accommodate placement.
	var surface := get_node_or_null("Surface/Terrain3D")
	if surface != null and surface.has_method("generate_nav_mesh_source_geometry"):
		var faces: PackedVector3Array = surface.generate_nav_mesh_source_geometry(AABB(Vector3(-29, -20, -29), Vector3(58, 42, 58)))
		if not faces.is_empty():
			var bounded := PackedVector3Array()
			for index in range(0, faces.size(), 3):
				if Vector2(faces[index].x, faces[index].z).length() <= enclosure_radius and Vector2(faces[index + 1].x, faces[index + 1].z).length() <= enclosure_radius and Vector2(faces[index + 2].x, faces[index + 2].z).length() <= enclosure_radius:
					bounded.append(faces[index])
					bounded.append(faces[index + 1])
					bounded.append(faces[index + 2])
			if not bounded.is_empty():
				source.add_faces(bounded, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(region.navigation_mesh, source)
	region.navigation_mesh = region.navigation_mesh


func wander_point(height: float) -> Vector3:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * minf(exploration_limit, enclosure_radius - 1.0)
	return Vector3(cos(angle) * radius, 0.0 if randf() < 0.65 else height, sin(angle) * radius)
