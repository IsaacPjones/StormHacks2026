extends SceneTree

const Production = preload("res://scripts/plant_production.gd")
const Categories = preload("res://scripts/resource_categories.gd")

var failed := false


func _initialize() -> void:
	call_deferred("run_check")


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)


func run_check() -> void:
	seed(14)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	for _frame in range(10):
		await physics_frame
	for plant_node in get_nodes_in_group("productive_plants"):
		plant_node.production_enabled = false
	var ant: CharacterBody3D = world.get_node("Ant")
	var isopod: CharacterBody3D = world.get_node("Isopod")
	for creature in get_nodes_in_group("ants"):
		if creature != ant:
			creature.set_physics_process(false)
	ant.food_detection_radius = 30.0
	ant.hunger_time_left = 1000.0
	isopod.detection_range = 30.0
	var plant: Node3D = world.get_node("NectarPlant")
	var nectar := Production.new()
	nectar.amount_per_drop = 1.0
	nectar.harvest_seconds = 0.1
	nectar.interval_seconds = 0.5
	nectar.initial_delay_seconds = 0.5
	nectar.max_active_drops = 1
	var leaves := Production.new()
	leaves.resource_category = Categories.Kind.DETRITUS
	leaves.resource_kind = &"leaf_scraps"
	leaves.amount_per_drop = 0.5
	leaves.initial_delay_seconds = 0.5
	leaves.interval_seconds = 0.5
	leaves.max_active_drops = 1
	var future := Production.new()
	future.resource_category = Categories.Kind.OTHER_FOOD
	future.resource_kind = &"pollen"
	future.initial_delay_seconds = 0.5
	future.interval_seconds = 0.5
	future.max_active_drops = 1
	plant.productions.assign([nectar, leaves, future])
	plant.reset_production_timers()
	plant.production_enabled = true
	ant.set_physics_process(false)
	isopod.set_physics_process(false)
	paused = true
	for _frame in range(30):
		await process_frame
	expect(get_nodes_in_group("resource_sources").is_empty() and plant.time_left[0] == 0.5, "Pause freezes plant production")
	paused = false
	Engine.time_scale = 4.0
	for _frame in range(15):
		await physics_frame
	Engine.time_scale = 1.0
	var food := get_nodes_in_group("food_sources")
	var detritus := get_nodes_in_group("detritus_sources")
	expect(food.size() == 1 and detritus.size() == 1 and get_nodes_in_group("resource_sources").size() == 3, "Fast-forward produces all three configured categories")
	if food.size() != 1 or detritus.size() != 1:
		quit(1)
		return
	var nectar_drop: Node3D = food[0]
	var leaf_drop: Node3D = detritus[0]
	var nectar_ref: WeakRef = weakref(nectar_drop)
	var leaf_ref: WeakRef = weakref(leaf_drop)
	expect(plant.produce_resource(0) == null and plant.produce_resource(1) == null, "Each production entry has its own live-drop limit")
	expect(nectar_drop.get("resource_kind") == &"nectar" and leaf_drop.get("resource_kind") == &"leaf_scraps", "Drops preserve their resource kinds")
	ant.accepted_resource_kinds.assign([&"sap"])
	expect(ant.find_nearby_food() == null, "A specialised ant diet rejects nectar")
	ant.accepted_resource_kinds.clear()
	expect(ant.find_nearby_food() == nectar_drop and isopod.find_nearby_detritus() == leaf_drop, "Ants and isopods discover only their own resources")
	plant.production_enabled = false
	ant.set_physics_process(true)
	isopod.set_physics_process(true)
	var home: AntHome = world.get_node("NavigationRegion3D/Home")
	for _frame in range(15000):
		await physics_frame
		if nectar_ref.get_ref() == null and leaf_ref.get_ref() == null and home.stored_portions > 0:
			break
	expect(nectar_ref.get_ref() == null and home.stored_portions == 1, "Ant harvests plant nectar and delivers it to the underground nest")
	expect(leaf_ref.get_ref() == null, "Isopod eats plant litter locally until empty")
	expect(get_nodes_in_group("detritus_sources").is_empty(), "Plant food depletion creates no orange peel scraps")
	expect(get_nodes_in_group("resource_sources").size() == 1, "Future-species food remains untouched")
	var replacement: Node3D = plant.produce_resource(1)
	expect(replacement != null, "Consuming a pile frees capacity for another drop")
	if replacement != null:
		var first_bite: float = replacement.consume(0.4)
		var last_bite: float = replacement.consume(5.0)
		expect(is_equal_approx(first_bite + last_bite, 0.5) and replacement.amount == 0.0 and replacement.consume(1.0) == 0.0, "Shared consumption cannot duplicate the last bite or go negative")
	if not failed:
		print("PLANT LOOP PASS: production, caps, diets, nectar delivery underground, litter cleanup, future food, pause, 4x, shared consumption")
	quit(1 if failed else 0)
