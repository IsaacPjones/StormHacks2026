extends CharacterBody3D

@export var animation_player: AnimationPlayer
@export var move_speed: float = 1.4
@export var turn_speed: float = 8.0
@export var wander_limit: float = 4.0

var target_position: Vector3
var wait_time_left: float = 0.0

var gravity: float = 9.8

var was_moving: bool = false

func _ready() -> void:
	var walk_animation: Animation = animation_player.get_animation("Take 001")
	walk_animation.loop_mode = Animation.LOOP_LINEAR

	animation_player.play_section("Take 001", 12.0, 14.529)
	animation_player.advance(0.0)
	animation_player.pause()

	choose_new_target()


func _physics_process(delta: float) -> void:
	# Apply gravity so the ant stays on the floor.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Start with no horizontal movement.
	velocity.x = 0.0
	velocity.z = 0.0

	if wait_time_left > 0.0:
		# Count down the pause before exploring again.
		wait_time_left = maxf(wait_time_left - delta, 0.0)

		if wait_time_left == 0.0:
			choose_new_target()

	else:
		var offset: Vector3 = target_position - global_position

		# Only consider horizontal distance to the target.
		offset.y = 0.0

		if offset.length() < 0.15:
			# Pause for a random amount of time.
			wait_time_left = randf_range(0.5, 1.5)

		else:
			var direction: Vector3 = offset.normalized()

			# Limit movement so we don't overshoot the destination.
			var speed: float = minf(move_speed, offset.length() / delta)

			velocity.x = direction.x * speed
			velocity.z = direction.z * speed

			# Gradually turn toward the direction of travel.
			var target_angle: float = atan2(-direction.x, -direction.z)

			rotation.y = lerp_angle(
				rotation.y,
				target_angle,
				minf(turn_speed * delta, 1.0)
			)

	move_and_slide()

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var is_moving: bool = horizontal_speed > 0.05

	if is_moving != was_moving or not animation_player.is_playing():
		animation_player.stop()

		if is_moving:
			animation_player.play_section("Take 001", 12.15, 14.529)
		else:
			animation_player.play_section("Take 001", 4.3, 11.9701)

		was_moving = is_moving

func choose_new_target() -> void:
	target_position = Vector3(
		randf_range(-wander_limit, wander_limit),
		global_position.y,
		randf_range(-wander_limit, wander_limit)
	)
