class_name AntHome
extends Node3D

signal food_changed(portions: int)

@export var stored_portions: int = 0

@onready var entrance: Marker3D = $Entrance
@onready var food_label: Label3D = $FoodLabel
@onready var food_pile: Node3D = $FoodPile


func _ready() -> void:
	add_to_group("ant_homes")
	update_food_display()


func get_arrival_position() -> Vector3:
	return entrance.global_position


func deposit_portion() -> void:
	stored_portions += 1
	update_food_display()
	food_changed.emit(stored_portions)
	print("Orange slice deposited. Home portions: ", stored_portions)


func take_portion() -> bool:
	# Remove the portion immediately so two ants cannot eat the same slice.
	if stored_portions <= 0:
		return false
	stored_portions -= 1
	update_food_display()
	food_changed.emit(stored_portions)
	return true


func update_food_display() -> void:
	food_label.text = "Home | Orange slices: %d" % stored_portions
	for child in food_pile.get_children():
		food_pile.remove_child(child)
		child.queue_free()

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.05)
	for index in range(mini(stored_portions, 12)):
		var slice := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.08
		mesh.material = material
		slice.mesh = mesh
		slice.position = Vector3((index % 4 - 1.5) * 0.25, 0.05, (index / 4) * 0.22)
		food_pile.add_child(slice)
