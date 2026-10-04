class_name DetritusSource
extends Node3D

const Categories = preload("res://scripts/resource_categories.gd")

signal amount_changed(remaining: float)
signal depleted

@export var resource_category: Categories.Kind = Categories.Kind.DETRITUS
@export_range(0.0, 1000.0, 0.1) var amount: float = 8.0
@export_range(0.1, 5.0, 0.05) var feeding_radius: float = 0.85

## Keep model replacements under this node so quantity scaling has a stable origin.
@export_node_path("Node3D") var visual_path: NodePath = ^"Visual"

@onready var visual: Node3D = get_node_or_null(visual_path) as Node3D

var initial_amount: float = 0.0
var initial_visual_scale := Vector3.ONE


func _ready() -> void:
	amount = maxf(amount, 0.0)
	initial_amount = amount
	if is_instance_valid(visual):
		initial_visual_scale = visual.scale
	else:
		push_warning("Detritus visual missing at '%s'. Put the model under Visual or set visual_path." % visual_path)
	add_to_group("detritus_sources")
	update_visual()
	if amount == 0.0:
		remove_from_group("detritus_sources")
		queue_free()


func get_feeding_position(from_position: Vector3) -> Vector3:
	var direction := from_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.FORWARD
	var point := global_position + direction.normalized() * feeding_radius
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var reachable := NavigationServer3D.map_get_closest_point(map, point)
	var offset := reachable - point
	# The old orange hole may persist until the next navigation update. Wait
	# for real access rather than feeding from a distant snapped path endpoint.
	if offset.length() > 0.4:
		return Vector3.INF
	return reachable


func consume(requested: float) -> float:
	if is_queued_for_deletion() or requested <= 0.0 or amount <= 0.0:
		return 0.0
	# All eaters share this transaction; the last bite cannot go below zero.
	var eaten: float = minf(requested, amount)
	amount = maxf(amount - eaten, 0.0)
	update_visual()
	amount_changed.emit(amount)
	if amount == 0.0:
		remove_from_group("detritus_sources")
		depleted.emit()
		queue_free()
	return eaten


func update_visual() -> void:
	if not is_instance_valid(visual):
		return
	var fraction: float = amount / initial_amount if initial_amount > 0.0 else 0.0
	visual.scale = initial_visual_scale * pow(fraction, 1.0 / 3.0)
