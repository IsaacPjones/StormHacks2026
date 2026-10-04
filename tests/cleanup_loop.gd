extends SceneTree

const Categories = preload("res://scripts/resource_categories.gd")
const SCRAPS: PackedScene = preload("res://scenes/scraps.tscn")
const ISOPOD: PackedScene = preload("res://scenes/isopod.tscn")

var scraps_spawned: int = 0
var scraps_reference: WeakRef
var scraps_shrank: bool = false
var failed: bool = false


func _initialize() -> void:
	call_deferred("run_check")


func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
		quit(1)


func run_check() -> void:
	seed(12)
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	# Isolate the existing orange cleanup regression from renewable plant food.
	for plant in get_nodes_in_group("productive_plants"):
		plant.set("production_enabled", false)
	await world.colony_ready
	for frame in range(20):
		await physics_frame
	var ants: Array[Node] = get_nodes_in_group("ants")
	var isopods: Array[Node] = get_nodes_in_group("isopods")
	expect(ants.size() == 5 and isopods.size() == 1, "Five ants and one isopod")
	var isopod: CharacterBody3D = isopods[0]
	var hud: CanvasLayer = world.get_node("ColonyHUD")
	var placement: Node3D = world.get_node("FoodPlacement")
	var camera: Camera3D = world.get_node("CameraRig/Camera3D")
	var home: AntHome = world.get_node("NavigationRegion3D/Home")
	for ant in ants:
		expect(ant.get("move_speed") >= 2.52 and ant.get("move_speed") <= 3.08, "Ant base speed doubled with existing variation")
		ant.set_physics_process(false)
	isopod.set("detection_range", 30.0)
	hud.get("pause_button").pressed.emit()
	hud.get("add_food_button").pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(Vector3(4, 0, 5))
	placement.call("_unhandled_input", click)
	for frame in range(3):
		await physics_frame
	var sources: Array[Node] = get_nodes_in_group("food_sources")
	expect(sources.size() == 1, "Player placement still spawns a physics orange while paused")
	var orange: FoodSource = sources[0]
	orange.portions = 2
	orange.harvest_seconds = 0.1
	orange.scraps_amount = 1.2
	orange.depleted.connect(func(pile: Node3D) -> void:
		scraps_spawned += 1
		scraps_reference = weakref(pile)
		expect(pile.resource_category == Categories.Kind.DETRITUS, "Orange leftovers are detritus")
		expect(absf(pile.global_position.y) < 0.1, "Scraps spawn on physical ground")
		expect(orange.collision_layer == 0, "Depleted orange stops blocking creatures immediately")
		expect(not orange.take_portion(), "No second ant can take the last portion")
		orange.leave_scraps()
		expect(get_nodes_in_group("detritus_sources").size() == 1, "Repeated depletion spawns exactly one pile")
		pile.amount_changed.connect(func(_remaining: float) -> void:
			if is_instance_valid(pile) and pile.get_node("Visual").scale.x < 1.0:
				scraps_shrank = true
		)
	)
	var frozen: Vector3 = orange.global_position
	for frame in range(10):
		await process_frame
	expect(orange.global_position == frozen, "Orange physics respects pause")
	hud.get("pause_button").pressed.emit()
	for frame in range(240):
		await physics_frame
	expect(orange.sleeping and world.get("food_obstacles").size() == 1, "Settled orange participates in existing navigation")
	expect(isopod.call("find_nearby_detritus") == null, "Isopod ignores harvestable ant food")
	for ant in ants:
		ant.set_physics_process(true)
	for frame in range(12000):
		await physics_frame
		if scraps_spawned == 1 and scraps_reference.get_ref() == null and home.stored_portions > 0:
			break
	expect(scraps_spawned == 1 and scraps_reference.get_ref() == null, "Ant harvesting creates scraps and isopod finishes them")
	expect(scraps_shrank, "Pile visibly shrinks while being eaten")
	expect(home.stored_portions > 0, "Ants still deliver harvested slices to home")
	expect(world.get("food_obstacles").is_empty(), "Depletion removes the invisible orange navigation obstacle")
	expect(not isopod.get("is_eating") and isopod.get("resource_target") == null, "Isopod resumes exploring after cleanup")
	for ant in ants:
		ant.set_physics_process(false)
	var piles_before: int = get_nodes_in_group("detritus_sources").size()
	expect(home.take_portion(), "Stored food remains consumable")
	expect(get_nodes_in_group("detritus_sources").size() == piles_before, "Nest consumption creates no scraps")
	# A future leaf uses the same detritus component without any isopod change.
	var leaf: Node3D = SCRAPS.instantiate()
	leaf.name = "FallenLeafTest"
	leaf.set("amount", 100.0)
	world.add_child(leaf)
	leaf.global_position = Vector3(6, 0, 3)
	isopod.global_position = Vector3(6.85, isopod.global_position.y, 3)
	isopod.set("resource_target", leaf)
	for frame in range(3):
		await physics_frame
	expect(isopod.get("is_eating"), "Isopod eats generic detritus locally")
	var amount_before: float = leaf.get("amount")
	var position_before: Vector3 = isopod.global_position
	hud.get("pause_button").pressed.emit()
	for frame in range(20):
		await process_frame
	expect(leaf.get("amount") == amount_before and isopod.global_position == position_before, "Pause freezes feeding and movement")
	hud.get("pause_button").pressed.emit()
	amount_before = leaf.get("amount")
	for frame in range(60):
		await process_frame
	var normal_consumption: float = amount_before - float(leaf.get("amount"))
	hud.get_node("Bar/Margin/Contents/Speed2").pressed.emit()
	amount_before = leaf.get("amount")
	for frame in range(60):
		await process_frame
	var fast_consumption: float = amount_before - float(leaf.get("amount"))
	expect(absf(normal_consumption - 0.8) < 0.1, "Inspector eating rate is per simulation second")
	expect(absf(fast_consumption - normal_consumption * 4.0) < 0.2, "4x playback scales feeding consistently")
	hud.get_node("Bar/Margin/Contents/Speed0").pressed.emit()
	hud.call("refresh_display")
	expect(hud.get("total_food").text == "Food  %d" % home.stored_portions, "Detritus is excluded from ant-food HUD total")
	# Shared transactions clamp quantities, even before queued deletion occurs.
	var race: Node3D = SCRAPS.instantiate()
	race.set("amount", 1.0)
	world.add_child(race)
	var first: float = race.consume(0.8)
	var second: float = race.consume(0.8)
	expect(absf(first + second - 1.0) < 0.00001 and race.amount == 0.0, "Concurrent last bites cannot overdraw resource")
	expect(race.consume(1.0) == 0.0, "Queued empty pile rejects additional bites")
	# Two real creatures finishing one pile must both release invalid targets.
	leaf.set("amount", 0.1)
	var companion: CharacterBody3D = ISOPOD.instantiate()
	world.add_child(companion)
	companion.global_position = Vector3(6.85, 0.2, 3)
	companion.set("resource_target", leaf)
	var leaf_ref: WeakRef = weakref(leaf)
	for frame in range(120):
		await physics_frame
	expect(leaf_ref.get_ref() == null, "Two isopods deplete shared scraps")
	expect(isopod.get("resource_target") == null and companion.get("resource_target") == null, "Both creatures release deleted pile references")
	expect(not isopod.get("is_eating") and not companion.get("is_eating"), "Both creatures return to exploration")
	if not failed:
		print("CLEANUP TEST PASS: placement, five faster ants, orange depletion once, navigation, shrinking scraps, local isopod meals, generic detritus, shared last bites, pause and 4x timing")
		quit(0)
