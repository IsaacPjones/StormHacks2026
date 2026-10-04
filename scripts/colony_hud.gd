extends CanvasLayer

@export var food_added_per_click: int = 16

@onready var ant_count: Label = $Panel/Margin/Contents/AntCount
@onready var stored_food: Label = $Panel/Margin/Contents/StoredFood
@onready var available_food: Label = $Panel/Margin/Contents/AvailableFood
@onready var warning: Label = $Panel/Margin/Contents/Warning
@onready var pause_button: Button = $Panel/Margin/Contents/Controls/Pause
@onready var speed_control: OptionButton = $Panel/Margin/Contents/Controls/Speed
@onready var add_food_button: Button = $Panel/Margin/Contents/AddFood

var refresh_time_left: float = 0.0


func _ready() -> void:
	pause_button.pressed.connect(toggle_pause)
	speed_control.item_selected.connect(set_speed)
	add_food_button.pressed.connect(add_food)
	add_food_button.text = "Add orange (+%d portions)" % food_added_per_click
	refresh_display()


func _process(delta: float) -> void:
	refresh_time_left -= delta
	if refresh_time_left <= 0.0:
		refresh_time_left = 0.2
		refresh_display()


func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	pause_button.text = "Resume" if get_tree().paused else "Pause"


func set_speed(index: int) -> void:
	Engine.time_scale = [1.0, 2.0, 4.0][index]


func add_food() -> void:
	# Refill an existing source: its collision and baked paths remain valid.
	var sources: Array[Node] = get_tree().get_nodes_in_group("food_sources")
	if sources.is_empty():
		return
	var source := sources[0] as FoodSource
	if is_instance_valid(source):
		source.add_portions(food_added_per_click)
	refresh_display()


func refresh_display() -> void:
	var ants: Array[Node] = get_tree().get_nodes_in_group("ants")
	var stored: int = 0
	var available: int = 0
	var hungry: int = 0
	var carried: int = 0
	for home in get_tree().get_nodes_in_group("ant_homes"):
		stored += int(home.get("stored_portions"))
	for food in get_tree().get_nodes_in_group("food_sources"):
		available += int(food.get("portions"))
	for ant in ants:
		if ant.get("has_food"):
			carried += 1
		if ant.get("hunger_time_left") <= 0.0 and not ant.get("is_eating"):
			hungry += 1

	ant_count.text = "Ants: %d" % ants.size()
	stored_food.text = "Stored food: %d slices" % stored
	available_food.text = "Orange: %d portions | Carrying: %d" % [available, carried]
	add_food_button.disabled = get_tree().get_nodes_in_group("food_sources").is_empty()
	warning.modulate = Color(1.0, 0.78, 0.4)
	if stored == 0 and available == 0 and carried == 0:
		warning.text = "Food exhausted. Add orange to feed the colony."
		warning.modulate = Color(1.0, 0.5, 0.4)
	elif hungry > 0 and stored == 0:
		warning.text = "%d hungry ants. Food needs to reach home." % hungry
	elif stored == 0:
		warning.text = "Nest empty. Ants are building the food supply."
	elif available == 0:
		warning.text = "Orange depleted. Add food before stores run out."
	elif stored < ants.size():
		warning.text = "Low stores: fewer than one slice per ant."
	else:
		warning.text = "Food is available at home."
		warning.modulate = Color(0.65, 0.88, 0.63)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
