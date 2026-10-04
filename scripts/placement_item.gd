class_name PlacementItem
extends Resource

enum Category { BUGS, PLANTS, FOOD }

@export var title: String = "Item"
@export var category: Category = Category.FOOD
@export var scene: PackedScene
@export_range(0.1, 5.0, 0.05) var radius: float = 0.6
@export_range(0.1, 10.0, 0.05) var height: float = 0.7
@export var spawn_offset: float = 0.1
@export_range(0.0, 45.0, 1.0) var max_slope_degrees: float = 8.0
@export var production_profile: PlantProduction
