extends RefCounted

const Item = preload("res://scripts/placement_item.gd")


static func items() -> Array[Item]:
	var result: Array[Item] = []
	result.append(make("Ant", Item.Category.BUGS, "res://scenes/ant.tscn", 0.6, 0.65, 0.1, 35))
	result.append(make("Isopod", Item.Category.BUGS, "res://scenes/isopod.tscn", 0.5, 0.6, 0.1, 35))
	result.append(make("Leaf-litter tree", Item.Category.PLANTS, "res://scenes/plant.tscn", 1.6, 5.8, 0, 8))
	result.append(make("Nectar plant", Item.Category.PLANTS, "res://scenes/nectar_plant.tscn", 0.65, 1.2, 0, 8))
	result.append(make("Sap plant", Item.Category.PLANTS, "res://scenes/sap_plant.tscn", 0.85, 1.4, 0, 8))
	var nectar := make("Nectar", Item.Category.FOOD, "res://scenes/plant_drop.tscn", 0.5, 0.3, 0, 8)
	nectar.production_profile = load("res://resources/plants/nectar.tres")
	result.append(nectar)
	var sap := make("Sap", Item.Category.FOOD, "res://scenes/plant_drop.tscn", 0.5, 0.3, 0, 8)
	sap.production_profile = load("res://resources/plants/sap.tres")
	result.append(sap)
	result.append(make("Leaf scraps", Item.Category.FOOD, "res://scenes/scraps.tscn", 0.85, 0.5, 0, 8))
	result.append(make("Orange", Item.Category.FOOD, "res://scenes/food.tscn", 1.55, 3.6, 2.05, 5))
	return result


static func make(title: String, category: int, path: String, radius: float, height: float, offset: float, slope: float) -> Item:
	var item := Item.new()
	item.title = title
	item.category = category as Item.Category
	item.scene = load(path)
	item.radius = radius
	item.height = height
	item.spawn_offset = offset
	item.max_slope_degrees = slope
	return item
