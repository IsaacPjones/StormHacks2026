extends Node3D

signal placement_changed(active: bool)
signal food_spawned(food: FoodSource)

const ORANGE_SCENE: PackedScene = preload("res://scenes/food.tscn")
const ORANGE_RADIUS: float = 1.4

@export var drop_height: float = 0.65
## Optional map-specific surface/footprint validator; the original map uses its box floor.
@export_node_path("Node") var placement_surface_provider: NodePath

var active: bool = false
var placement_valid: bool = false
var ground_position := Vector3.ZERO
var spawn_requested: bool = false
var requested_screen_position := Vector2.ZERO
var preview: MeshInstance3D
var preview_material: StandardMaterial3D

@onready var camera: Camera3D = get_parent().get_node("CameraRig/Camera3D")


func _ready() -> void:
	preview = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = ORANGE_RADIUS + 0.1
	mesh.bottom_radius = ORANGE_RADIUS + 0.1
	mesh.height = 0.035
	preview_material = StandardMaterial3D.new()
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = preview_material
	preview.mesh = mesh
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	preview.hide()


func toggle_placement() -> void:
	set_active(not active)


func set_active(value: bool) -> void:
	active = value
	spawn_requested = false
	preview.visible = active
	placement_changed.emit(active)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_active(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			set_active(false)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			spawn_requested = true
			requested_screen_position = event.position
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not active:
		return
	var mouse := requested_screen_position if spawn_requested else get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var end := origin + camera.project_ray_normal(mouse) * 200.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	preview.visible = not hit.is_empty() and mouse.y > 48.0
	placement_valid = false
	if preview.visible:
		ground_position = hit.position
		preview.global_position = ground_position + Vector3(0, 0.025, 0)
		placement_valid = hit.collider.is_in_group("placement_ground") and hit.normal.y >= 0.97 and can_place_at(ground_position)
		preview_material.albedo_color = Color(0.35, 0.85, 0.45, 0.45) if placement_valid else Color(0.95, 0.3, 0.2, 0.45)
	if spawn_requested:
		spawn_requested = false
		if placement_valid:
			spawn_orange(ground_position)
			set_active(false)


func can_place_at(point: Vector3) -> bool:
	# Reserve the whole footprint inside the actual ground shape.
	var clearance: float = ORANGE_RADIUS + 0.15
	var ground_rid: RID
	if not placement_surface_provider.is_empty():
		var provider: Node = get_node(placement_surface_provider)
		var surface: Dictionary = provider.get_food_placement_surface(point, clearance)
		if surface.is_empty():
			return false
		ground_rid = surface.rid
	else:
		var ground: StaticBody3D = get_parent().get_node("NavigationRegion3D/Ground")
		var floor_shape: CollisionShape3D = ground.get_node("CollisionShape3D")
		var box := floor_shape.shape as BoxShape3D
		var local_point := floor_shape.to_local(point)
		if absf(local_point.x) > box.size.x * 0.5 - clearance or absf(local_point.z) > box.size.z * 0.5 - clearance:
			return false
		ground_rid = ground.get_rid()
	for home in get_tree().get_nodes_in_group("ant_homes"):
		var offset: Vector3 = home.get_arrival_position() - point
		var height_difference: float = absf(offset.y)
		offset.y = 0.0
		if height_difference <= 0.6 and offset.length() < clearance + 1.0:
			return false
	# Check both landing space and the short drop, including other oranges.
	var sphere := SphereShape3D.new()
	sphere.radius = clearance
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 5
	query.exclude = [ground_rid]
	for height in [clearance, clearance + drop_height]:
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3(0, height, 0))
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return false
	return true


func spawn_orange(point: Vector3) -> FoodSource:
	var food: FoodSource = ORANGE_SCENE.instantiate()
	get_parent().add_child(food)
	food.global_position = point + Vector3(0, ORANGE_RADIUS + drop_height, 0)
	food.rotation.y = randf_range(-PI, PI)
	food_spawned.emit(food)
	return food
