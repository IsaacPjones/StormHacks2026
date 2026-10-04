extends CharacterBody3D

const Categories = preload("res://scripts/resource_categories.gd")
const Detritus = preload("res://scripts/detritus.gd")

@export var animation_player: AnimationPlayer
@export var walk_animation: StringName = &"Walk"
## Ground speed that matches the walking clip at its original playback rate.
@export_range(0.01, 10.0, 0.05) var walk_animation_reference_speed: float = 1.1
@export var move_speed: float = 1.1
@export var turn_speed: float = 7.0
@export var wander_limit: float = 9.0
@export var detection_range: float = 5.0
## Empty accepts all detritus; useful when introducing more specialised species.
@export var accepted_resource_kinds: Array[StringName] = []
@export var feeding_distance: float = 0.2
@export var arrival_height_tolerance: float = 0.6
@export_range(0.01, 100.0, 0.05) var eating_rate: float = 0.8

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

var resource_target: Detritus
var is_eating: bool = false
var navigation_ready: bool = false
var scan_time_left: float = 0.0
var wait_time_left: float = 0.0
var gravity: float = 9.8


func _ready() -> void:
	floor_snap_length = 0.6
	add_to_group("isopods")
	navigation_agent.path_desired_distance = 0.3
	navigation_agent.target_desired_distance = 0.1
	navigation_agent.avoidance_enabled = false
	scan_time_left = randf_range(0.0, 0.5)
	if is_instance_valid(animation_player) and animation_player.has_animation(walk_animation):
		animation_player.get_animation(walk_animation).loop_mode = Animation.LOOP_LINEAR
		animation_player.play(walk_animation)
		animation_player.advance(0.0)
		animation_player.pause()


func _physics_process(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	var map: RID = navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		move_and_slide()
		update_animation()
		return
	if not navigation_ready:
		if not is_on_floor():
			move_and_slide()
			update_animation()
			return
		var ground := NavigationServer3D.map_get_closest_point(map, global_position)
		navigation_agent.path_height_offset = ground.y - global_position.y
		navigation_ready = true
		choose_wander_target()

	if is_instance_valid(resource_target):
		if resource_target.is_queued_for_deletion() or resource_target.amount <= 0.0 or not accepts_detritus(resource_target):
			resume_exploring()
	elif resource_target != null or is_eating:
		resume_exploring()

	if not is_instance_valid(resource_target):
		scan_time_left -= delta
		if scan_time_left <= 0.0:
			scan_time_left = 0.5
			resource_target = find_nearby_detritus()
			if is_instance_valid(resource_target):
				wait_time_left = 0.0
				navigation_agent.target_position = resource_target.get_feeding_position(global_position)

	if is_instance_valid(resource_target):
		var point: Vector3 = resource_target.get_feeding_position(global_position)
		if not point.is_finite():
			resume_exploring()
		elif horizontal_distance_to(point) <= feeding_distance and absf(point.y - global_position.y) <= arrival_height_tolerance and is_on_floor():
			is_eating = true
			resource_target.consume(eating_rate * delta)
			if not is_instance_valid(resource_target) or resource_target.amount <= 0.0:
				resume_exploring()
		else:
			is_eating = false
			if navigation_agent.target_position.distance_to(point) > 0.15:
				navigation_agent.target_position = point
			if navigation_agent.is_navigation_finished():
				resume_exploring()
			else:
				follow_path(delta)
	else:
		wander(delta)

	move_and_slide()
	update_animation()


func update_animation() -> void:
	if not is_instance_valid(animation_player) or not animation_player.has_animation(walk_animation):
		return
	var actual_velocity := get_real_velocity()
	var horizontal_speed := Vector2(actual_velocity.x, actual_velocity.z).length()
	if horizontal_speed > 0.05:
		animation_player.speed_scale = horizontal_speed / walk_animation_reference_speed
		if not animation_player.is_playing():
			# Resume the same walk cycle rather than restarting it after a pause.
			animation_player.play(walk_animation)
	else:
		# This asset has only a walking clip, so hold the current pose at rest.
		animation_player.pause()


func accepts_detritus(resource: Node3D) -> bool:
	return resource.get("resource_category") == Categories.Kind.DETRITUS and (accepted_resource_kinds.is_empty() or resource.get("resource_kind") in accepted_resource_kinds)


func find_nearby_detritus() -> Detritus:
	var nearest: Detritus = null
	var nearest_distance: float = detection_range
	var map: RID = navigation_agent.get_navigation_map()
	for node in get_tree().get_nodes_in_group("detritus_sources"):
		var resource := node as Detritus
		if not is_instance_valid(resource) or resource.is_queued_for_deletion():
			continue
		if resource.amount <= 0.0 or not accepts_detritus(resource):
			continue
		var distance: float = horizontal_distance_to(resource.global_position)
		if distance >= nearest_distance:
			continue
		var point: Vector3 = resource.get_feeding_position(global_position)
		if not point.is_finite():
			continue
		var path := NavigationServer3D.map_get_path(map, global_position, point, true, navigation_agent.navigation_layers)
		if path.is_empty():
			continue
		var end_offset: Vector3 = path[path.size() - 1] - point
		end_offset.y = 0.0
		if end_offset.length() > feeding_distance:
			continue
		nearest = resource
		nearest_distance = distance
	return nearest


func resume_exploring() -> void:
	resource_target = null
	is_eating = false
	scan_time_left = 0.5
	wait_time_left = randf_range(0.3, 1.0)
	choose_wander_target()


func choose_wander_target() -> void:
	var point := Vector3(randf_range(-wander_limit, wander_limit), global_position.y, randf_range(-wander_limit, wander_limit))
	navigation_agent.target_position = NavigationServer3D.map_get_closest_point(navigation_agent.get_navigation_map(), point)


func wander(delta: float) -> void:
	if wait_time_left > 0.0:
		wait_time_left = maxf(wait_time_left - delta, 0.0)
		return
	if navigation_agent.is_navigation_finished():
		wait_time_left = randf_range(0.5, 2.0)
		choose_wander_target()
		return
	follow_path(delta)


func follow_path(delta: float) -> void:
	var offset := navigation_agent.get_next_path_position() - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.000001:
		return
	var direction := offset.normalized()
	var speed: float = minf(move_speed, offset.length() / delta)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(turn_speed * delta, 1.0))


func horizontal_distance_to(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.length()
