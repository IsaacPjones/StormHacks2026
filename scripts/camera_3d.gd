extends Node3D

signal selection_changed(bug: Node3D)

@export var rotation_speed: float = 0.004
@export var pan_speed: float = 0.0012
@export var min_distance: float = 3.0
@export var max_distance: float = 45.0
@export var pan_limit: float = 28.0
@export var home_position := Vector3(0, -1.5, 0)
@export var home_distance: float = 43.0
@export var home_pitch_degrees: float = -32.0

@onready var camera: Camera3D = $Camera3D

var selected_bug: Node3D
var following := false
var orbiting := false
var panning := false
var distance := 43.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera.near = 0.08
	camera.far = 200.0
	reset_view()


func reset_view() -> void:
	stop_following()
	position = home_position
	rotation = Vector3(deg_to_rad(home_pitch_degrees), 0.0, 0.0)
	distance = clampf(home_distance, min_distance, max_distance)
	camera.position = Vector3(0, 0, distance)


func stop_following() -> void:
	following = false


func clear_selection() -> void:
	selected_bug = null
	following = false
	selection_changed.emit(null)


func follow_selected() -> void:
	if is_instance_valid(selected_bug):
		following = true
		distance = clampf(6.0, min_distance, max_distance)


func _process(delta: float) -> void:
	if selected_bug != null and not is_instance_valid(selected_bug):
		clear_selection()
	if following and is_instance_valid(selected_bug):
		var real_delta := delta / maxf(Engine.time_scale, 0.01)
		global_position = global_position.lerp(selected_bug.global_position + Vector3.UP * 0.5, 1.0 - exp(-8.0 * real_delta))
	camera.position.z = distance
	if following and is_instance_valid(selected_bug):
		var query := PhysicsRayQueryParameters3D.create(global_position, to_global(Vector3(0, 0, distance)), 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			camera.position.z = maxf(0.4, global_position.distance_to(hit.position) - 0.2)


func _input(event: InputEvent) -> void:
	# Releases must clear drags even when the pointer is now over a UI panel.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = false
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = false


func _unhandled_input(event: InputEvent) -> void:
	if get_parent().get_node("ColonyHUD").pause_overlay != null and get_parent().get_node("ColonyHUD").pause_overlay.visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F and is_instance_valid(selected_bug):
			follow_selected()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			reset_view()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if orbiting:
			rotation.y -= event.relative.x * rotation_speed
			rotation.x = clampf(rotation.x - event.relative.y * rotation_speed, deg_to_rad(-82), deg_to_rad(-10))
		elif panning:
			stop_following()
			var right := global_basis.x
			var back := global_basis.z
			right.y = 0.0
			back.y = 0.0
			global_position += (-right.normalized() * event.relative.x - back.normalized() * event.relative.y) * pan_speed * distance
			global_position.x = clampf(global_position.x, -pan_limit, pan_limit)
			global_position.z = clampf(global_position.z, -pan_limit, pan_limit)
		if orbiting or panning:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				orbiting = true
			MOUSE_BUTTON_MIDDLE:
				panning = true
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(min_distance, distance / 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(max_distance, distance * 1.15)
			MOUSE_BUTTON_LEFT:
				var placement: Node = get_parent().get_node("FoodPlacement")
				if placement.active:
					return
				select_at(event.position)
		get_viewport().set_input_as_handled()


func select_at(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 200.0, 7)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit.collider.is_in_group("ants") or hit.collider.is_in_group("isopods")):
		selected_bug = hit.collider
		selection_changed.emit(selected_bug)
	else:
		clear_selection()
