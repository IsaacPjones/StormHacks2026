extends SceneTree


func _initialize() -> void:
	call_deferred("run_check")


func wait_world() -> Node3D:
	await process_frame
	await process_frame
	var world: Node3D = current_scene
	if not world.map_ready:
		await world.colony_ready
	return world


func run_check() -> void:
	var saves: Node = root.get_node("TerrariumSave")
	saves.save_path = "res://tests/_menu_flow.json"
	if FileAccess.file_exists(saves.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.save_path))
	var menu: Control = load("res://scenes/start_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	assert(menu.continue_button.disabled)
	menu.new_terrarium()
	var world: Node3D = await wait_world()
	assert(get_nodes_in_group("ants").size() == 5 and get_nodes_in_group("isopods").size() == 1)
	assert(world.get_node("NavigationRegion3D/Home").stored_portions == 0)
	var hud: Node = world.get_node("ColonyHUD")
	hud.toggle_pause()
	assert(paused and not hud.pause_overlay.visible)
	hud.open_pause_menu()
	assert(paused and hud.pause_overlay.visible)
	world.get_node("NavigationRegion3D/Home").stored_portions = 9
	world.get_node("Ecosystem").simulation_time = 10.0
	assert(saves.save_world(world))
	hud.exit_confirmation.confirmed.emit()
	await process_frame
	await process_frame
	menu = current_scene
	assert(not menu.continue_button.disabled)
	menu.continue_terrarium()
	world = await wait_world()
	assert(world.get_node("NavigationRegion3D/Home").stored_portions == 9)
	assert(world.get_node("Ecosystem").simulation_time >= 10.0 and world.get_node("Ecosystem").simulation_time < 10.2)
	hud = world.get_node("ColonyHUD")
	hud.exit_confirmation.confirmed.emit()
	await process_frame
	await process_frame
	menu = current_scene
	menu.new_terrarium()
	assert(menu.confirmation.visible and not saves.pending_new)
	assert(saves.read_save().homes[0].stored == 9)
	menu.confirmation.confirmed.emit()
	world = await wait_world()
	assert(world.get_node("NavigationRegion3D/Home").stored_portions == 0)
	await process_frame
	assert(saves.has_valid_save() and saves.read_save().homes[0].stored == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.save_path))
	print("MENU FLOW PASS: New starting state, separate pause/menu, Save/Return/Continue, replacement confirmation, reset slot")
	quit(0)
