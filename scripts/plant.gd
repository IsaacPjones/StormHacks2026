extends Node3D

const Production = preload("res://scripts/plant_production.gd")
const DROP_SCENE: PackedScene = preload("res://scenes/plant_drop.tscn")
const Categories = preload("res://scripts/resource_categories.gd")

signal resource_produced(drop: Node3D, production_index: int)

@export var production_enabled: bool = true
## A plant can produce several kinds independently, or none at all.
@export var productions: Array[Production] = []
@export_range(0.1, 20.0, 0.1) var drop_radius_min: float = 2.0
@export_range(0.1, 20.0, 0.1) var drop_radius_max: float = 3.0
@export_range(0.1, 10.0, 0.1) var drop_spacing: float = 0.65

var time_left: Array[float] = []
var active_drops: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("productive_plants")
	reset_production_timers()


func reset_production_timers() -> void:
	time_left.clear()
	for production in productions:
		time_left.append(maxf(production.initial_delay_seconds if production.initial_delay_seconds >= 0.0 else production.interval_seconds, 0.0) if production != null else 0.0)


func _physics_process(delta: float) -> void:
	if not production_enabled:
		return
	if time_left.size() != productions.size():
		reset_production_timers()
	for index in range(productions.size()):
		var production: Production = productions[index]
		if production == null:
			continue
		time_left[index] = maxf(time_left[index] - delta, 0.0)
		if time_left[index] > 0.0:
			continue
		var produced := false
		for _drop in range(production.drops_per_cycle):
			if produce_resource(index) != null:
				produced = true
		# Retry a full plant or blocked ground rather than building up a backlog.
		time_left[index] = maxf(production.interval_seconds, 0.1) if produced else 2.0


func produce_resource(index: int) -> Node3D:
	if index < 0 or index >= productions.size() or productions[index] == null:
		return null
	var production: Production = productions[index]
	var count := 0
	for record in active_drops.duplicate():
		var drop: Node = record.reference.get_ref()
		if not is_instance_valid(drop) or drop.is_queued_for_deletion():
			active_drops.erase(record)
		elif record.index == index:
			count += 1
	if count >= production.max_active_drops:
		return null
	var ground_point := find_drop_position()
	if not ground_point.is_finite():
		return null
	var drop: Node3D = DROP_SCENE.instantiate()
	drop.set("resource_category", production.resource_category)
	drop.set("resource_kind", production.resource_kind)
	drop.set("amount", maxf(1.0, floor(production.amount_per_drop)) if production.resource_category == Categories.Kind.ANT_FOOD else production.amount_per_drop)
	drop.set("harvest_seconds", production.harvest_seconds)
	var visual: Node3D = drop.get_node("Visual")
	if production.drop_visual_scene != null:
		for child in visual.get_children():
			visual.remove_child(child)
			child.queue_free()
		visual.add_child(production.drop_visual_scene.instantiate())
	else:
		var mesh: MeshInstance3D = visual.get_node("Placeholder")
		var material := StandardMaterial3D.new()
		material.albedo_color = production.placeholder_color
		material.roughness = 0.8
		mesh.material_override = material
	drop.name = "%sDrop" % production.resource_kind.capitalize()
	# Drops live outside the plant, so replacing or deleting its model is safe.
	var container: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	container.add_child(drop)
	drop.global_position = ground_point
	active_drops.append({"index": index, "reference": weakref(drop)})
	resource_produced.emit(drop, index)
	return drop


func find_drop_position() -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	for _attempt in range(16):
		var angle := randf() * TAU
		var radius := randf_range(minf(drop_radius_min, drop_radius_max), maxf(drop_radius_min, drop_radius_max))
		var point := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point + Vector3.DOWN * 4.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider.is_in_group("placement_ground") or hit.normal.y < 0.97:
			continue
		var floor_point: Vector3 = hit.position
		var navigable := NavigationServer3D.map_get_closest_point(map, floor_point)
		var offset := navigable - floor_point
		if absf(offset.y) > 0.6 or Vector2(offset.x, offset.z).length() > 0.2:
			continue
		var crowded := false
		for resource in get_tree().get_nodes_in_group("resource_sources"):
			if resource.global_position.distance_to(floor_point) < drop_spacing:
				crowded = true
				break
		if not crowded:
			return floor_point
	return Vector3.INF
