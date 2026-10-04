extends Node

const Item = preload("res://scripts/placement_item.gd")

@onready var world: Node3D = get_parent()


func ground_surface(point: Vector3, radius: float, max_slope: float = 8.0) -> Dictionary:
	if Vector2(point.x, point.z).length() + radius > world.enclosure_radius:
		return {}
	var center: Dictionary = {}
	for index in range(9):
		var offset := Vector3.ZERO if index == 0 else Vector3(cos(TAU * (index - 1) / 8.0), 0.0, sin(TAU * (index - 1) / 8.0)) * radius
		var sample_point := point + offset
		var slope_height := radius * tan(deg_to_rad(max_slope)) + 0.15
		var query := PhysicsRayQueryParameters3D.create(sample_point + Vector3.UP * slope_height, sample_point + Vector3.DOWN * slope_height, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider.is_in_group("placement_ground") or hit.normal.y < cos(deg_to_rad(max_slope)):
			return {}
		if index == 0:
			center = hit
	return center


func reachable(point: Vector3) -> bool:
	var map: RID = world.get_node("NavigationRegion3D").get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var snapped := NavigationServer3D.map_get_closest_point(map, point)
	if snapped.distance_to(point) > 0.65:
		return false
	var anchors := get_tree().get_nodes_in_group("ant_homes") + get_tree().get_nodes_in_group("ants") + get_tree().get_nodes_in_group("isopods")
	for anchor in anchors:
		var path := NavigationServer3D.map_get_path(map, anchor.global_position, snapped, true)
		if not path.is_empty() and path[path.size() - 1].distance_to(snapped) < 0.25:
			return true
	return false


func can_place(point: Vector3, item: Item) -> bool:
	if not world.map_ready or ground_surface(point, item.radius, item.max_slope_degrees).is_empty() or not reachable(point):
		return false
	# Do not exclude the terrain RID: it also contains tunnel walls and ceilings.
	var shape := CylinderShape3D.new()
	shape.radius = item.radius
	shape.height = item.height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (item.height * 0.5 + item.radius * tan(deg_to_rad(item.max_slope_degrees)) + 0.08))
	if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	for plant in get_tree().get_nodes_in_group("productive_plants"):
		if plant.global_position.distance_to(point) < item.radius + 0.8:
			return false
	for home in get_tree().get_nodes_in_group("ant_homes"):
		if home.global_position.distance_to(point) < item.radius + 0.8:
			return false
	# Physics shape registration is deferred; reserve new objects immediately.
	for object in get_tree().get_nodes_in_group("dynamic_objects"):
		var separation: Vector3 = object.global_position - point
		if absf(separation.y) < item.height + float(object.get_meta("placement_height", 1.0)) and Vector2(separation.x, separation.z).length() < item.radius + float(object.get_meta("placement_radius", 0.5)):
			return false
	if item.category == Item.Category.FOOD:
		# Check at least one accessible gathering side before dropping the orange.
		var found_access := false
		var access_radius := 1.9 if item.scene.resource_path == "res://scenes/food.tscn" else (0.85 if item.scene.resource_path == "res://scenes/scraps.tscn" else 0.5)
		for index in range(8):
			var side := point + Vector3(cos(index * TAU / 8.0), 0, sin(index * TAU / 8.0)) * access_radius
			if reachable(side) and not ground_surface(side, 0.55, 35.0).is_empty():
				found_access = true
				break
		if not found_access:
			return false
	return true


func spawn_item(item: Item, point: Vector3, newborn: bool = false) -> Node3D:
	if item.category == Item.Category.BUGS:
		var is_ant := item.scene.resource_path == "res://scenes/ant.tscn"
		var group := "ants" if is_ant else "isopods"
		var ecosystem: Node = world.get_node("Ecosystem")
		if get_tree().get_nodes_in_group(group).size() >= (ecosystem.ant_population_cap if is_ant else ecosystem.isopod_population_cap):
			world.get_node("ColonyHUD").show_notice("Population cap reached")
			return null
	if not can_place(point, item):
		return null
	var instance: Node3D = item.scene.instantiate()
	if item.production_profile != null:
		instance.set("resource_category", item.production_profile.resource_category)
		instance.set("resource_kind", item.production_profile.resource_kind)
		instance.set("amount", item.production_profile.amount_per_drop)
		instance.set("harvest_seconds", item.production_profile.harvest_seconds)
		instance.set_meta("production_profile", item.production_profile)
		TerrariumSave.apply_resource_visual(instance, item.production_profile)
	instance.set_meta("player_placed", not newborn)
	instance.set_meta("placement_radius", item.radius)
	instance.set_meta("placement_height", item.height)
	instance.add_to_group("dynamic_objects")
	if newborn:
		instance.set("age_seconds", 0.0)
	var parent: Node = world.get_node("NavigationRegion3D") if item.category == Item.Category.PLANTS else world
	parent.add_child(instance)
	instance.global_position = point + Vector3.UP * item.spawn_offset
	if instance is CharacterBody3D:
		instance.set("wander_limit", world.exploration_limit)
	if item.category == Item.Category.PLANTS or item.category == Item.Category.FOOD:
		add_pick_area(instance, item.radius, item.height)
	if item.category == Item.Category.PLANTS:
		add_plant_collision(instance, item.radius, item.height)
		verify_plant_routes.call_deferred(instance)
	return instance


func add_plant_collision(instance: Node3D, radius: float, height: float) -> void:
	if not instance.find_children("*", "StaticBody3D", true, false).is_empty():
		return
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = minf(radius, 0.4)
	shape.height = height
	collider.shape = shape
	collider.position.y = height * 0.5
	body.add_child(collider)
	instance.add_child(body)


func add_pick_area(instance: Node3D, radius: float, height: float) -> void:
	var area := Area3D.new()
	area.name = "PlacementPickArea"
	area.collision_layer = 16
	area.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	area.position.y = height * 0.5
	area.add_child(collision)
	instance.add_child(area)


func find_safe_point(origin: Vector3, item: Item, search_radius: float = 3.0) -> Vector3:
	var map: RID = world.get_node("NavigationRegion3D").get_navigation_map()
	for _attempt in range(32):
		var angle := randf() * TAU
		var candidate := origin + Vector3(cos(angle), 0, sin(angle)) * randf_range(1.0, search_radius)
		candidate = NavigationServer3D.map_get_closest_point(map, candidate)
		if absf(candidate.y - origin.y) > 1.2:
			continue
		var query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.4, candidate + Vector3.DOWN * 1.0, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and can_place(hit.position, item):
			return hit.position
	return Vector3.INF


func verify_plant_routes(plant: Node3D) -> void:
	await get_tree().physics_frame
	world.update_food_navigation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(world.get_node("NavigationRegion3D").get_navigation_map())
	var safe := true
	var map: RID = world.get_node("NavigationRegion3D").get_navigation_map()
	for ant in get_tree().get_nodes_in_group("ants"):
		for home in get_tree().get_nodes_in_group("ant_homes"):
			var path := NavigationServer3D.map_get_path(map, ant.global_position, home.get_arrival_position(), true)
			if path.is_empty() or path[path.size() - 1].distance_to(home.get_arrival_position()) > 0.65:
				safe = false
	if not safe and is_instance_valid(plant):
		plant.get_parent().remove_child(plant)
		plant.queue_free()
		world.update_food_navigation()
		world.get_node("ColonyHUD").show_notice("Plant removed: it would block the nest route")
