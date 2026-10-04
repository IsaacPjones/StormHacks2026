extends "res://scripts/detritus.gd"

@export_range(0.1, 60.0, 0.1) var harvest_seconds: float = 2.0

var portions: int:
	get:
		return int(floor(amount))


func _ready() -> void:
	if resource_category == Categories.Kind.ANT_FOOD:
		amount = maxf(1.0, floor(amount))
	super._ready()


func get_gather_position(from_position: Vector3 = Vector3.INF) -> Vector3:
	return get_feeding_position(from_position if from_position.is_finite() else global_position + Vector3.FORWARD)


func take_portion() -> bool:
	if resource_category != Categories.Kind.ANT_FOOD or is_queued_for_deletion() or portions <= 0:
		return false
	return consume(1.0) == 1.0
