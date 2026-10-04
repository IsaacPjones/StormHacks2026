extends Node3D

signal placement_changed(active: bool)
signal food_spawned(food: FoodSource)
signal item_spawned(item: Node3D)

const Catalog = preload("res://scripts/placement_catalog.gd")
const Item = preload("res://scripts/placement_item.gd")

@export var drop_height: float = 0.65
@export_node_path("Node") var placement_surface_provider: NodePath

var active := false
var removing := false
var placement_valid := false
var ground_position := Vector3.ZERO
var spawn_requested := false
var requested_screen_position := Vector2.ZERO
var selected_item: Item
var preview: MeshInstance3D
var preview_material: StandardMaterial3D

@onready var world: Node3D = get_parent()
@onready var camera: Camera3D = world.get_node("CameraRig/Camera3D")
@onready var service: Node = world.get_node("SpawnService")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	selected_item = Catalog.items()[-1]
	preview = MeshInstance3D.new()
	preview_material = StandardMaterial3D.new()
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	update_preview_mesh()
	preview.hide()


func begin_placement(item: Item) -> void:
	selected_item = item
	removing = false
	update_preview_mesh()
	set_active(true)


func begin_removal() -> void:
	removing = true
	set_active(true)


func update_preview_mesh() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = selected_item.radius
	mesh.bottom_radius = selected_item.radius
	mesh.height = 0.045
	mesh.material = preview_material
	preview.mesh = mesh


func toggle_placement() -> void:
	set_active(not active)


func set_active(value: bool) -> void:
	active = value
	spawn_requested = false
	if preview != null:
		preview.visible = active and not removing
	placement_changed.emit(active)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_active(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if pointer_over_ui(event.position):
			return
		spawn_requested = true
		requested_screen_position = event.position
		get_viewport().set_input_as_handled()


func pointer_over_ui(screen_position: Vector2) -> bool:
	return world.get_node("ColonyHUD").blocks_world_input(screen_position)


func _physics_process(_delta: float) -> void:
	if not active:
		return
	var mouse := requested_screen_position if spawn_requested else get_viewport().get_mouse_position()
	if pointer_over_ui(mouse):
		preview.hide()
		spawn_requested = false
		return
	if removing:
		preview.hide()
		if spawn_requested:
			spawn_requested = false
			remove_at(mouse)
		return
	var origin := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(mouse) * 200.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	preview.visible = not hit.is_empty()
	placement_valid = false
	if preview.visible:
		ground_position = hit.position
		preview.global_position = ground_position + Vector3.UP * 0.04
		placement_valid = hit.collider.is_in_group("placement_ground") and can_place_at(ground_position)
		preview_material.albedo_color = Color(0.3, 0.85, 0.4, 0.5) if placement_valid else Color(0.95, 0.25, 0.2, 0.5)
	if spawn_requested:
		spawn_requested = false
		if placement_valid:
			var spawned: Node3D = service.spawn_item(selected_item, ground_position)
			if spawned != null:
				item_spawned.emit(spawned)
				if spawned is FoodSource:
					food_spawned.emit(spawned)
				set_active(false)


func can_place_at(point: Vector3) -> bool:
	return service.can_place(point, selected_item)


func spawn_orange(point: Vector3) -> FoodSource:
	return service.spawn_item(Catalog.items()[-1], point) as FoodSource


func remove_at(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 200.0, 21)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var node: Node = hit.collider
	while node != null and node != world:
		if node.get_meta("player_placed", false) and (node.is_in_group("productive_plants") or node.is_in_group("resource_sources")):
			node.get_parent().remove_child(node)
			node.queue_free()
			world.update_food_navigation()
			set_active(false)
			return
		node = node.get_parent()
