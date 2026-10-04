extends Node3D

const ANT_SCENE: PackedScene = preload("res://scenes/ant.tscn")

@export_range(1, 20, 1) var starting_ant_count: int = 5
@export var exploration_limit: float = 9.0


func _ready() -> void:
	# Allow the existing navigation region to synchronize before placing ants.
	initialize_colony.call_deferred()


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
