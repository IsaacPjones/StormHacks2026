extends Control

var continue_button: Button
var message: Label
var confirmation: ConfirmationDialog


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.1, 0.075)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(340, 0)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var title := Label.new()
	title.text = "TerraSphere"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	column.add_child(title)
	add_button(column, "New Terrarium", new_terrarium)
	continue_button = add_button(column, "Continue", continue_terrarium)
	continue_button.disabled = not TerrariumSave.has_valid_save()
	add_button(column, "Quit", func() -> void: get_tree().quit())
	message = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 340
	message.text = "Build a food supply, water the soil, and watch your colony grow."
	if FileAccess.file_exists(TerrariumSave.save_path) and continue_button.disabled:
		message.text = "The save is missing or invalid. You can start a new terrarium."
	column.add_child(message)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Replace saved terrarium?"
	confirmation.dialog_text = "New Terrarium replaces the existing save with the starting state."
	confirmation.confirmed.connect(start_new)
	add_child(confirmation)


func add_button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func new_terrarium() -> void:
	if TerrariumSave.has_valid_save():
		confirmation.popup_centered()
	else:
		start_new()


func start_new() -> void:
	TerrariumSave.pending_load = {}
	TerrariumSave.pending_new = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func continue_terrarium() -> void:
	var data := TerrariumSave.read_save()
	if data.is_empty():
		continue_button.disabled = true
		message.text = "The save cannot be loaded. Start a new terrarium."
		return
	TerrariumSave.pending_load = data
	TerrariumSave.pending_new = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")
