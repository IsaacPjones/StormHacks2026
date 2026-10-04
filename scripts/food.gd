class_name FoodSource
extends RigidBody3D

const Categories = preload("res://scripts/resource_categories.gd")
const SCRAPS_SCENE: PackedScene = preload("res://scenes/scraps.tscn")

signal portions_changed(portions_left: int)
signal depleted(scraps: Node3D)

@export var resource_category: Categories.Kind = Categories.Kind.ANT_FOOD
@export var portions: int = 8
@export var harvest_seconds: float = 10.0
@export var gather_radius: float = 1.9
@export_range(0.0, 1000.0, 0.1) var scraps_amount: float = 8.0

var has_depleted: bool = false


func _ready() -> void:
	add_to_group("food_sources")
	if portions <= 0:
		leave_scraps.call_deferred()


func get_gather_position(from_position: Vector3 = Vector3.INF) -> Vector3:
	# A rolling body's local marker rotates with it. Keep access on the ground
	# outside its collision instead, on the side nearest the approaching ant.
	var direction := Vector3.FORWARD
	if from_position.is_finite():
		direction = from_position - global_position
		direction.y = 0.0
		if direction.length_squared() < 0.001:
			direction = Vector3.FORWARD
		direction = direction.normalized()
	var point := global_position + direction * gather_radius
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	return point


func take_portion() -> bool:
	if has_depleted or portions <= 0:
		return false

	portions -= 1
	portions_changed.emit(portions)
	print("Orange portions remaining: ", portions)
	if portions == 0:
		leave_scraps()
	return true


func add_portions(amount: int) -> void:
	if has_depleted or amount <= 0:
		return
	portions += amount
	portions_changed.emit(portions)


func leave_scraps() -> void:
	if has_depleted:
		return
	has_depleted = true
	portions = 0
	remove_from_group("food_sources")
	# Disable the orange immediately; no invisible physics body may block the
	# pile. The colony's existing obstacle check removes its baked nav hole.
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.set_deferred("disabled", true)
	hide()
	var scraps: Node3D = null
	if scraps_amount > 0.0:
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.5,
			global_position + Vector3.DOWN * 10.0,
			1
		)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var ground_point: Vector3 = hit.position if not hit.is_empty() else global_position - Vector3.UP * 1.4
		scraps = SCRAPS_SCENE.instantiate()
		scraps.set("amount", scraps_amount)
		get_parent().add_child(scraps)
		scraps.global_position = ground_point
	depleted.emit(scraps)
	queue_free()
