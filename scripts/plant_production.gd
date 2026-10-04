class_name PlantProduction
extends Resource

const Categories = preload("res://scripts/resource_categories.gd")

## Category controls who uses the drop; kind distinguishes nectar, sap, leaves, etc.
@export var resource_category: Categories.Kind = Categories.Kind.ANT_FOOD
@export var resource_kind: StringName = &"nectar"
@export_range(0.1, 3600.0, 0.1) var interval_seconds: float = 35.0
## Negative means wait one interval before the first drop.
@export_range(-1.0, 3600.0, 0.1) var initial_delay_seconds: float = -1.0
@export_range(1, 20, 1) var drops_per_cycle: int = 1
## Ant food uses whole portions. Detritus supports fractional amounts.
@export_range(0.1, 1000.0, 0.1) var amount_per_drop: float = 2.0
@export_range(1, 50, 1) var max_active_drops: int = 4
@export_range(0.1, 60.0, 0.1) var harvest_seconds: float = 2.0
@export var placeholder_color := Color(0.95, 0.65, 0.12)
## Optional model scene; only visuals belong here, not food behaviour or collision.
@export var drop_visual_scene: PackedScene
