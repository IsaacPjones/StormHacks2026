extends Node3D

const ANT_SCENE: PackedScene = preload("res://scenes/ant.tscn")

@export_range(1, 20, 1) var starting_ant_count: int = 5
@export var exploration_limit: float = 9.0

var food_obstacles: Dictionary = {}
var obstacle_check_left: float = 0.0


func _ready() -> void:
	# Bake only the static enclosure. Player-dropped food must not leave fixed
	# holes in the navigation mesh after it moves.
	$NavigationRegion3D.bake_navigation_mesh(false)
	# Allow the existing navigation region to synchronize before placing ants.
	initialize_colony.call_deferred()


func _physics_process(delta: float) -> void:
	obstacle_check_left -= delta
	if obstacle_check_left > 0.0:
		return
	obstacle_check_left = 0.5
	var settled: Dictionary = {}
	var changed: bool = false
	for food in get_tree().get_nodes_in_group("food_sources"):
		var body := food as RigidBody3D
		if not is_instance_valid(body) or not body.sleeping:
			continue
		var key: int = body.get_instance_id()
		settled[key] = body.global_position
		if not food_obstacles.has(key) or food_obstacles[key].distance_to(body.global_position) > 0.25:
			changed = true
	if settled.size() != food_obstacles.size():
		changed = true
	if changed:
		food_obstacles = settled
		update_food_navigation()


func update_food_navigation() -> void:
	# Baking parses static bodies. Temporary copies of sleeping food supply
	# obstacle geometry without freezing the real physics items.
	var region: NavigationRegion3D = $NavigationRegion3D
	var proxies: Array[StaticBody3D] = []
	for food in get_tree().get_nodes_in_group("food_sources"):
		if not food_obstacles.has(food.get_instance_id()):
			continue
		var collider: CollisionShape3D = food.get_node("CollisionShape3D")
		var proxy := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = collider.shape
		proxy.add_child(shape)
		region.add_child(proxy)
		proxy.global_transform = collider.global_transform
		proxies.append(proxy)
	region.bake_navigation_mesh(false)
	for proxy in proxies:
		region.remove_child(proxy)
		proxy.queue_free()


func initialize_colony() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var home: Node3D = $NavigationRegion3D/Home
	var map: RID = $NavigationRegion3D.get_navigation_map()
	while NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame

	var existing_ants: Array[Node] = get_tree().get_nodes_in_group("ants")
	for ant in existing_ants:
		ant.set("wander_limit", exploration_limit)

	for index in range(existing_ants.size(), starting_ant_count):
		var ant: CharacterBody3D = ANT_SCENE.instantiate()
		ant.set("wander_limit", exploration_limit)
		var angle: float = TAU * float(index) / float(starting_ant_count)
		var spawn_point: Vector3 = home.global_position + Vector3(cos(angle), 0, sin(angle)) * 1.8
		spawn_point = NavigationServer3D.map_get_closest_point(map, spawn_point)
		add_child(ant)
		ant.global_position = spawn_point + Vector3(0, 0.1, 0)
