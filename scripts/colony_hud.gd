extends CanvasLayer

var ant_count: Label
var isopod_count: Label
var stored_food: Label
var moisture_label: Label
var warning: Label
var pause_button: Button
var placement_hint: Label
var root_ui: Control
var contents: HBoxContainer
var placement_items: Array = []
var notice: Label
var selection_label: Label
var reproduction_label: Label
var pause_overlay: Control
var exit_confirmation: ConfirmationDialog
var notice_time_left := 0.0
var pause_message: Label
var milestone_label: Label
var refresh_time_left := 0.0
var status_panel: PanelContainer
var hint_panel: PanelContainer

@onready var world: Node3D = get_parent()
@onready var placement: Node = world.get_node("FoodPlacement")
@onready var ecosystem: Node = world.get_node("Ecosystem")


func _ready() -> void:
	placement_items = preload("res://scripts/placement_catalog.gd").items()
	root_ui = Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_theme_font_size_override("font_size", 14)
	add_child(root_ui)
	var bar := PanelContainer.new()
	bar.name = "Bar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.22, 0.17, 0.97)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", style)
	root_ui.add_child(bar)
	contents = HBoxContainer.new()
	contents.add_theme_constant_override("separation", 6)
	bar.add_child(contents)
	pause_button = add_button(contents, "Pause", toggle_pause)
	pause_button.name = "Pause"
	var speed_group := ButtonGroup.new()
	for index in range(3):
		var button := add_button(contents, ["1x", "2x", "4x"][index], set_speed.bind(index))
		button.name = "Speed%d" % index
		button.toggle_mode = true
		button.button_group = speed_group
		button.button_pressed = index == 0
	contents.add_child(VSeparator.new())
	ant_count = add_label(contents, "Ants: 0")
	var add_ant := add_button(contents, "+", add_bug.bind(0))
	add_ant.name = "AddAnt"
	add_ant.tooltip_text = "Add an ant on reachable ground"
	isopod_count = add_label(contents, "Isopods: 0")
	var add_isopod := add_button(contents, "+", add_bug.bind(1))
	add_isopod.name = "AddIsopod"
	add_isopod.tooltip_text = "Add an isopod on reachable ground"
	stored_food = add_label(contents, "Stored food: 0")
	moisture_label = add_label(contents, "Soil moisture: 60%")
	moisture_label.tooltip_text = "Simplified soil water level for this enclosure."
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(spacer)
	add_button(contents, "Water", func() -> void:
		ecosystem.water()
		refresh_display()
	)
	add_button(contents, "Reset View", func() -> void:
		if world.get_node("CameraRig").has_method("reset_view"):
			world.get_node("CameraRig").reset_view()
	)
	add_button(contents, "Orange", place_orange)
	add_button(contents, "Menu", open_pause_menu)
	status_panel = PanelContainer.new()
	status_panel.position = Vector2(12, 58)
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", panel_style())
	root_ui.add_child(status_panel)
	var status_column := VBoxContainer.new()
	status_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_child(status_column)
	warning = add_label(status_column, "")
	notice = add_label(status_column, "")
	selection_label = add_label(status_column, "")
	hint_panel = PanelContainer.new()
	hint_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_panel.offset_top = -62
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_theme_stylebox_override("panel", panel_style())
	root_ui.add_child(hint_panel)
	placement_hint = Label.new()
	placement_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placement_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placement_hint.text = "Click clear ground · Escape cancels"
	hint_panel.add_child(placement_hint)
	hint_panel.hide()
	placement.placement_changed.connect(func(active: bool) -> void: hint_panel.visible = active)
	refresh_display()
	build_pause_menu()


func add_button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	var normal := panel_style()
	normal.bg_color = Color(0.24, 0.38, 0.29)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.33, 0.50, 0.37)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.39, 0.60, 0.42)
	button.add_theme_stylebox_override("pressed", pressed)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.22, 0.17, 0.95)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func add_label(parent: Node, caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _process(delta: float) -> void:
	hint_panel.position.x = maxf(12.0, (root_ui.size.x - hint_panel.size.x) * 0.5)
	if notice_time_left > 0.0:
		notice_time_left = maxf(0.0, notice_time_left - delta / maxf(Engine.time_scale, 0.01))
		if notice_time_left == 0.0 and notice != null:
			notice.text = ""
	refresh_time_left -= delta
	if refresh_time_left <= 0.0:
		refresh_time_left = 0.2
		refresh_display()


func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_button.text = "Play" if get_tree().paused else "Pause"
	if not get_tree().paused and pause_overlay != null:
		pause_overlay.hide()


func set_speed(index: int) -> void:
	Engine.time_scale = [1.0, 2.0, 4.0][index]


func refresh_display() -> void:
	for index in range(3):
		contents.get_node("Speed%d" % index).button_pressed = is_equal_approx(Engine.time_scale, [1.0, 2.0, 4.0][index])
	pause_button.text = "Play" if get_tree().paused else "Pause"
	var ants := get_tree().get_nodes_in_group("ants")
	var stored := 0
	var available := 0
	for home in get_tree().get_nodes_in_group("ant_homes"):
		stored += home.stored_portions
	for food in get_tree().get_nodes_in_group("food_sources"):
		if not food.is_queued_for_deletion():
			available += food.portions
	ant_count.text = "Ants: %d" % ants.size()
	isopod_count.text = "Isopods: %d" % get_tree().get_nodes_in_group("isopods").size()
	stored_food.text = "Stored food: %d" % stored
	moisture_label.text = "Soil moisture: %d%%" % roundi(ecosystem.soil_moisture)
	warning.text = "Nest empty — gather or add food" if stored == 0 else ("Low stored food" if stored < ants.size() else "")
	if stored == 0 and available == 0:
		warning.text = "Add an orange to feed your ants"
	warning.modulate = Color(1.0, 0.78, 0.4)
	if reproduction_label != null:
		reproduction_label.text = "Nest: %s · Isopods: %s" % [ecosystem.ant_status, ecosystem.isopod_status]
	if milestone_label != null:
		milestone_label.text = ecosystem.milestone_status
	if not ecosystem.moisture_warning().is_empty():
		warning.text = ecosystem.moisture_warning()
	if selection_label != null:
		var rig: Node3D = world.get_node("CameraRig")
		if is_instance_valid(rig.selected_bug):
			selection_label.text = "%s — %s" % ["Ant" if rig.selected_bug.is_in_group("ants") else "Isopod", rig.selected_bug.get_activity_label() if rig.selected_bug.has_method("get_activity_label") else "Exploring"]
		else:
			selection_label.text = ""
	for label in [warning, notice, selection_label]:
		label.visible = not label.text.is_empty()
	status_panel.visible = warning.visible or notice.visible or selection_label.visible


func add_bug(index: int) -> void:
	if not world.map_ready:
		show_notice("Preparing the enclosure...")
		return
	var item: Resource = placement_items[index]
	var group := "ants" if index == 0 else "isopods"
	var cap: int = ecosystem.ant_population_cap if index == 0 else ecosystem.isopod_population_cap
	if get_tree().get_nodes_in_group(group).size() >= cap:
		show_notice("Population cap reached")
		return
	var service: Node = world.get_node("SpawnService")
	var center: Vector3 = world.get_node("CameraRig").global_position
	center.y = 0.0
	for attempt in range(4):
		var origin: Vector3 = center if attempt == 0 else world.wander_point(0.0)
		var point: Vector3 = service.find_safe_point(origin, item, 8.0)
		if point.is_finite() and service.spawn_item(item, point) != null:
			refresh_display()
			return
	show_notice("No clear, reachable ground for another bug")


func place_orange() -> void:
	placement.begin_placement(placement_items[-1])
	placement_hint.text = "Click green ground to place · Escape to cancel"


func blocks_world_input(point: Vector2) -> bool:
	if pause_overlay != null and pause_overlay.visible:
		return true
	if point.y < root_ui.get_node("Bar").size.y:
		return true
	return false


func show_notice(message: String) -> void:
	if notice != null:
		notice.text = message
		notice_time_left = 7.0
		if pause_message != null:
			pause_message.text = message


func build_pause_menu() -> void:
	pause_overlay = Control.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.add_child(pause_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(310, 0)
	panel.add_theme_stylebox_override("panel", panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	add_label(column, "Terrarium paused")
	add_button(column, "Resume", resume_simulation)
	add_button(column, "Save", func() -> void:
		show_notice("Terrarium saved" if TerrariumSave.save_world(world) else TerrariumSave.last_error)
	)
	add_button(column, "Return to Menu", func() -> void: exit_confirmation.popup_centered())
	reproduction_label = add_label(column, "")
	reproduction_label.add_theme_font_size_override("font_size", 12)
	milestone_label = add_label(column, "")
	milestone_label.add_theme_font_size_override("font_size", 12)
	add_label(column, "Right drag: orbit · Middle drag: pan\nWheel: zoom · R: reset view\nClick a bug, F: follow · Escape: stop / menu")
	pause_message = add_label(column, "")
	pause_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_message.custom_minimum_size.x = 300
	pause_overlay.hide()
	exit_confirmation = ConfirmationDialog.new()
	exit_confirmation.title = "Return to Menu?"
	exit_confirmation.dialog_text = "Unsaved changes will be lost. Choose Save first to keep them."
	exit_confirmation.confirmed.connect(func() -> void:
		get_tree().paused = false
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	)
	root_ui.add_child(exit_confirmation)


func open_pause_menu() -> void:
	placement.set_active(false)
	get_tree().paused = true
	pause_overlay.show()
	pause_button.text = "Play"


func resume_simulation() -> void:
	get_tree().paused = false
	pause_overlay.hide()
	pause_button.text = "Pause"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if placement.active:
			placement.set_active(false)
		elif world.get_node("CameraRig").following:
			world.get_node("CameraRig").stop_following()
		else:
			if pause_overlay.visible:
				resume_simulation()
			else:
				open_pause_menu()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
