extends CharacterBody3D

@export var animation_player: AnimationPlayer
@export var move_speed: float = 1.4
@export var turn_speed: float = 8.0
@export var wander_limit: float = 4.0

@export var food_detection_radius: float = 5.0
@export var gather_distance: float = 0.35
@export var hunger_interval: float = 120.0
@export var eat_seconds: float = 2.0

@onready var carried_food: Node3D = $CarriedFood

var food_target: FoodSource
var is_harvesting: bool = false
var harvest_time_left: float = 0.0
var has_food: bool = false
var food_scan_time_left: float = 0.0
var home_target: Node
var hunger_time_left: float = 0.0
var eat_time_left: float = 0.0
var is_eating: bool = false
var home_retry_time_left: float = 0.0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

var target_position: Vector3
var wait_time_left: float = 0.0
var gravity: float = 9.8
var was_moving: bool = false
var navigation_ready: bool = false


func _ready() -> void:
	add_to_group("ants")
	carried_food.hide()
	# Stagger activity without changing the configured recurring hunger interval.
	hunger_time_left = hunger_interval * randf_range(0.7, 1.3)
	food_scan_time_left = randf_range(0.0, 0.5)
	wait_time_left = randf_range(0.2, 1.5)
	move_speed *= randf_range(0.9, 1.1)
	var animation: Animation = animation_player.get_animation("Take 001")
	animation.loop_mode = Animation.LOOP_LINEAR
	animation_player.play_section("Take 001", 4.3, 11.9701)

	# How close we must get to each path point and destination.
	navigation_agent.path_desired_distance = 0.15
	navigation_agent.target_desired_distance = 0.15
	navigation_agent.avoidance_enabled = false


func _physics_process(delta: float) -> void:
	# Apply gravity so the ant stays on the floor.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	velocity.x = 0.0
	velocity.z = 0.0

	hunger_time_left = maxf(hunger_time_left - delta, 0.0)
	if update_home_behavior(delta):
		pass
	elif not update_food_behavior(delta):
		update_navigation(delta)

	move_and_slide()
	update_animation()


func update_navigation(delta: float) -> void:
	var navigation_map: RID = navigation_agent.get_navigation_map()

	# Wait until Godot has synchronized the navigation map.
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return

	if not navigation_ready:
		# Let the ant settle onto the ground first.
		if not is_on_floor():
			return

		# Match path height to the ant's origin on our flat floor.
		var ground_point: Vector3 = NavigationServer3D.map_get_closest_point(
			navigation_map,
			global_position
		)
		navigation_agent.path_height_offset = ground_point.y - global_position.y

		navigation_ready = true
		choose_new_target()

	if wait_time_left > 0.0:
		wait_time_left = maxf(wait_time_left - delta, 0.0)

		if wait_time_left == 0.0:
			choose_new_target()

		return

	if navigation_agent.is_navigation_finished():
		wait_time_left = randf_range(0.5, 1.5)
		return

	# Follow the next point along the path.
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	var offset: Vector3 = next_position - global_position
	offset.y = 0.0

	if offset.length() < 0.001:
		return

	var direction: Vector3 = offset.normalized()
	var speed: float = minf(move_speed, offset.length() / delta)

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Gradually face the direction we are travelling.
	var target_angle: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(
		rotation.y,
		target_angle,
		minf(turn_speed * delta, 1.0)
	)


func choose_new_target() -> void:
	var random_position := Vector3(
		randf_range(-wander_limit, wander_limit),
		global_position.y,
		randf_range(-wander_limit, wander_limit)
	)

	# Snap the random destination onto the navigation mesh.
	target_position = NavigationServer3D.map_get_closest_point(
		navigation_agent.get_navigation_map(),
		random_position
	)

	navigation_agent.target_position = target_position


func update_animation() -> void:
	var actual_velocity: Vector3 = get_real_velocity()
	var horizontal_speed: float = Vector2(
		actual_velocity.x,
		actual_velocity.z
	).length()
	var is_moving: bool = horizontal_speed > 0.05

	if is_moving != was_moving or not animation_player.is_playing():
		animation_player.stop()

		if is_moving:
			animation_player.play_section("Take 001", 12.15, 14.529)
		else:
			animation_player.play_section("Take 001", 4.3, 11.9701)

		was_moving = is_moving

func update_food_behavior(delta: float) -> bool:
	if not navigation_ready or has_food:
		return false

	# Handle food disappearing or running out.
	if is_instance_valid(food_target):
		if food_target.portions <= 0:
			stop_seeking_food()
	else:
		food_target = null
		is_harvesting = false

	if is_instance_valid(food_target):
		# Gathering uses ground-plane distance, just like food detection.
		var gather_offset: Vector3 = food_target.get_gather_position() - global_position
		gather_offset.y = 0.0
		var distance: float = gather_offset.length()

		if is_harvesting:
			# If pushed away, return to the gathering point.
			if distance > gather_distance:
				is_harvesting = false
				navigation_agent.target_position = food_target.get_gather_position()
				return false

			harvest_time_left = maxf(harvest_time_left - delta, 0.0)

			if Engine.get_physics_frames() % 60 == 0:
				print("Harvest seconds left: ", harvest_time_left)
			if harvest_time_left == 0.0:
				if food_target.take_portion():
					has_food = true
					carried_food.show()
					print("Ant collected an orange slice!")

				stop_seeking_food()
				if has_food:
					begin_home_trip(false)

			return true

		# Start gathering as soon as we are close enough.
		if distance <= gather_distance and is_on_floor():
			is_harvesting = true
			harvest_time_left = food_target.harvest_seconds
			wait_time_left = 0.0
			print("Ant started harvesting. Duration: ", harvest_time_left)
			return true

		# A finished path does not always mean the food was reached.
		if navigation_agent.is_navigation_finished():
			print("Cannot reach GatherPoint. Distance: ", distance)
			stop_seeking_food()
			return true

		# Let the existing navigation code follow the food path.
		return false

	# Look for nearby food twice per second.
	food_scan_time_left -= delta

	if food_scan_time_left <= 0.0:
		food_scan_time_left = 0.5
		food_target = find_nearby_food()

		if is_instance_valid(food_target):
			wait_time_left = 0.0
			navigation_agent.target_position = food_target.get_gather_position()

	return false


func find_nearby_food() -> FoodSource:
	var nearest_food: FoodSource = null
	var nearest_distance: float = food_detection_radius

	for node in get_tree().get_nodes_in_group("food_sources"):
		var food := node as FoodSource

		if not is_instance_valid(food):
			continue

		if food.portions <= 0:
			continue

		var offset_to_food: Vector3 = (
			food.get_gather_position() - global_position
		)
		offset_to_food.y = 0.0

		var distance: float = offset_to_food.length()
		if Engine.get_physics_frames() % 60 == 0:
			print(
				"Food distance: ", snappedf(distance, 0.01),
				" | Required: ", gather_distance,
				" | On floor: ", is_on_floor(),
				" | Harvesting: ", is_harvesting
			)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_food = food

	return nearest_food


func stop_seeking_food() -> void:
	food_target = null
	is_harvesting = false
	harvest_time_left = 0.0
	food_scan_time_left = 2.0
	wait_time_left = 0.0
	choose_new_target()


func horizontal_distance_to(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.length()


func begin_home_trip(require_food: bool) -> void:
	home_target = null
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group("ant_homes"):
		var home := node as AntHome
		if not is_instance_valid(home):
			continue
		if require_food and home.stored_portions <= 0:
			continue
		var distance := horizontal_distance_to(home.get_arrival_position())
		if distance < nearest_distance:
			nearest_distance = distance
			home_target = home

	if is_instance_valid(home_target):
		food_target = null
		is_harvesting = false
		harvest_time_left = 0.0
		wait_time_left = 0.0
		home_retry_time_left = 0.0
		navigation_agent.target_position = home_target.get_arrival_position()


func update_home_behavior(delta: float) -> bool:
	if not navigation_ready:
		return false

	if is_eating:
		eat_time_left = maxf(eat_time_left - delta, 0.0)
		if eat_time_left == 0.0:
			is_eating = false
			hunger_time_left = hunger_interval
			print("Ant finished eating an orange slice.")
			stop_seeking_food()
		return true

	if not is_instance_valid(home_target):
		home_target = null
		if has_food:
			begin_home_trip(false)
		elif hunger_time_left == 0.0 and not is_harvesting:
			begin_home_trip(true)

	if not is_instance_valid(home_target):
		return false

	# A different ant may have consumed the last stored slice on our way home.
	if not has_food and home_target.stored_portions <= 0:
		home_target = null
		stop_seeking_food()
		return true

	if horizontal_distance_to(home_target.get_arrival_position()) <= gather_distance and is_on_floor():
		if has_food:
			home_target.deposit_portion()
			has_food = false
			carried_food.hide()
		elif home_target.take_portion():
			is_eating = true
			eat_time_left = eat_seconds
			print("Ant started eating a stored orange slice.")
		home_target = null
		stop_seeking_food()
		return true

	# Retry an unreachable destination without discarding the carried slice.
	# Do not let the wandering logic replace the home destination.
	if navigation_agent.is_navigation_finished():
		home_retry_time_left = maxf(home_retry_time_left - delta, 0.0)
		if home_retry_time_left == 0.0:
			navigation_agent.target_position = home_target.get_arrival_position()
			home_retry_time_left = 1.0
		return true

	update_navigation(delta)
	return true
