extends SceneTree


func _initialize() -> void:
	call_deferred("run_check")


func run_check() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await world.colony_ready
	var hud: CanvasLayer = world.get_node("ColonyHUD")
	hud.refresh_display()
	assert(hud.ant_count.text == "Ants: 5")
	assert(hud.isopod_count.text == "Isopods: 1")
	assert(hud.stored_food.text.begins_with("Stored food:"))
	assert(hud.moisture_label.text.begins_with("Soil moisture:"))
	assert(hud.find_child("TotalFood", true, false) == null)
	var placement: Node = world.get_node("FoodPlacement")
	placement.begin_placement(preload("res://scripts/placement_catalog.gd").items()[0])
	await process_frame
	var count_before := get_nodes_in_group("ants").size()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = hud.pause_button.get_global_rect().get_center()
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	assert(paused and get_nodes_in_group("ants").size() == count_before)
	placement.set_active(false)
	for index in range(6):
		click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = hud.contents.get_node("AddAnt").get_global_rect().get_center()
		root.push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		root.push_input(click, true)
	assert(get_nodes_in_group("ants").size() == count_before + 6, "Rapid plus clicks each spawn one ant, including while paused")
	hud.contents.get_node("AddIsopod").pressed.emit()
	assert(get_nodes_in_group("isopods").size() == 2)
	assert(not placement.active)
	ecosystem_cap_check(world, hud)
	hud.place_orange()
	assert(placement.active and placement.selected_item.scene.resource_path == "res://scenes/food.tscn")
	placement.set_active(false)
	var rig: Node3D = world.get_node("CameraRig")
	paused = true
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	rig._unhandled_input(button)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20, 10)
	var before: Vector3 = rig.rotation
	rig._unhandled_input(motion)
	assert(rig.rotation != before)
	rig.reset_view()
	assert(is_equal_approx(rig.distance, rig.home_distance))
	rig.selected_bug = world.get_node("Ant")
	rig.follow_selected()
	for _frame in range(10):
		await process_frame
	assert(rig.following)
	rig.stop_following()
	assert(not rig.following)
	paused = false
	print("UI CAMERA PASS: rapid paused quick-add, population caps, orange placement, UI click isolation, counts, paused orbit and follow")
	quit(0)


func ecosystem_cap_check(world: Node3D, hud: Node) -> void:
	var ecosystem: Node = world.get_node("Ecosystem")
	var previous_cap: int = ecosystem.ant_population_cap
	ecosystem.ant_population_cap = get_nodes_in_group("ants").size()
	hud.add_bug(0)
	assert(get_nodes_in_group("ants").size() == ecosystem.ant_population_cap)
	ecosystem.ant_population_cap = previous_cap
