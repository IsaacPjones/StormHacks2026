extends Node3D

@export var rotation_speed: float = 0.01
@export var pan_speed: float = 0.005
@export var min_distance: float = 2.0
@export var max_distance: float = 40.0

@onready var camera: Camera3D = $Camera3D


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Rotate left and right around the map.
			rotation.y -= event.relative.x * rotation_speed

			# Tilt, keeping the camera above the ground.
			rotation.x = clampf(
				rotation.x - event.relative.y * rotation_speed,
				deg_to_rad(-85.0),
				deg_to_rad(-15.0)
			)

		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			# Find camera-relative directions along the ground.
			var right: Vector3 = global_transform.basis.x
			var backward: Vector3 = global_transform.basis.z

			right.y = 0.0
			backward.y = 0.0
			right = right.normalized()
			backward = backward.normalized()

			# Pan faster when zoomed farther out.
			var movement: Vector3 = (
				-right * event.relative.x
				-backward * event.relative.y
			)

			global_position += movement * pan_speed * camera.position.z

	elif event is InputEventMouseButton:
		if not event.pressed:
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.position.z = clampf(
				camera.position.z / 1.15,
				min_distance,
				max_distance
			)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.position.z = clampf(
				camera.position.z * 1.15,
				min_distance,
				max_distance
			)
