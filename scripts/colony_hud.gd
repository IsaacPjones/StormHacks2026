extends CanvasLayer

const Categories = preload("res://scripts/resource_categories.gd")

@onready var ant_count: Label = $Bar/Margin/Contents/AntCount
@onready var total_food: Label = $Bar/Margin/Contents/TotalFood
@onready var stored_food: Label = $Bar/Margin/Contents/StoredFood
@onready var warning: Label = $Bar/Margin/Contents/Warning
@onready var pause_button: Button = $Bar/Margin/Contents/Pause
@onready var add_food_button: Button = $Bar/Margin/Contents/AddFood
@onready var placement_hint: Label = $PlacementHint
@onready var placement: Node = get_parent().get_node("FoodPlacement")

var refresh_time_left: float = 0.0


func _ready() -> void:
	pause_button.pressed.connect(toggle_pause)
	for index in range(3):
		var button: Button = $Bar/Margin/Contents.get_node("Speed%d" % index)
		button.pressed.connect(set_speed.bind(index))
	add_food_button.pressed.connect(placement.toggle_placement)
	placement.placement_changed.connect(update_placement)
	placement.food_spawned.connect(func(_food: FoodSource) -> void: refresh_display())
	refresh_display()


func _process(delta: float) -> void:
	refresh_time_left -= delta
	if refresh_time_left <= 0.0:
		refresh_time_left = 0.2
		refresh_display()


func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_button.text = "Play" if get_tree().paused else "Pause"
	pause_button.button_pressed = get_tree().paused


func set_speed(index: int) -> void:
	Engine.time_scale = [1.0, 2.0, 4.0][index]
	var button: Button = $Bar/Margin/Contents.get_node("Speed%d" % index)
	button.button_pressed = true


func update_placement(active: bool) -> void:
	add_food_button.button_pressed = active
	placement_hint.visible = active
	add_food_button.text = "Cancel orange" if active else "Place orange"


func refresh_display() -> void:
	var ants: Array[Node] = get_tree().get_nodes_in_group("ants")
	var stored: int = 0
	var available: int = 0
	var hungry: int = 0
	var carried: int = 0
	for home in get_tree().get_nodes_in_group("ant_homes"):
		stored += int(home.get("stored_portions"))
	for food in get_tree().get_nodes_in_group("food_sources"):
		if food.get("resource_category") == Categories.Kind.ANT_FOOD:
			available += int(food.get("portions"))
	for ant in ants:
		if ant.get("has_food"):
			carried += 1
		if ant.get("hunger_time_left") <= 0.0 and not ant.get("is_eating"):
			hungry += 1

	ant_count.text = "Ants  %d" % ants.size()
	total_food.text = "Food  %d" % (available + stored + carried)
	total_food.tooltip_text = "Total portions: %d in resources, %d stored, %d carried" % [available, stored, carried]
	stored_food.text = "Stored  %d" % stored
	warning.modulate = Color(1.0, 0.78, 0.4)
	if stored == 0 and available == 0 and carried == 0:
		warning.text = "No food"
		warning.tooltip_text = "Place food in the enclosure to feed the colony."
		warning.modulate = Color(1.0, 0.5, 0.4)
	elif hungry > 0 and stored == 0:
		warning.text = "Hungry  %d" % hungry
		warning.tooltip_text = "Hungry ants need food delivered to home."
	elif stored == 0:
		warning.text = "Nest empty"
		warning.tooltip_text = "Ants need to gather and deliver food."
	elif available == 0 or stored < ants.size():
		warning.text = "Low supply"
		warning.tooltip_text = "Add food to build up the colony's reserves."
	else:
		warning.text = "Fed"
		warning.tooltip_text = "Food is available at home."
		warning.modulate = Color(0.65, 0.88, 0.63)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
