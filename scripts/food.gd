class_name FoodSource
extends Node3D

signal portions_changed(portions_left: int)

@export var portions: int = 16
@export var harvest_seconds: float = 10.0

@onready var gather_point: Marker3D = $GatherPoint


func _ready() -> void:
	add_to_group("food_sources")


func get_gather_position() -> Vector3:
	return gather_point.global_position


func take_portion() -> bool:
	if portions <= 0:
		return false

	portions -= 1
	portions_changed.emit(portions)
	print("Orange portions remaining: ", portions)
	return true


func add_portions(amount: int) -> void:
	if amount <= 0:
		return
	portions += amount
	portions_changed.emit(portions)
