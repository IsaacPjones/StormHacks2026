extends Node

## Simplified enclosure-wide gameplay moisture, not atmospheric humidity.
@export_range(0.0, 100.0, 1.0) var soil_moisture: float = 60.0
@export_range(0.0, 100.0, 1.0) var water_amount: float = 20.0
@export_range(0.0, 1.0, 0.001) var evaporation_per_second: float = 0.025
@export_range(0.0, 3.0, 0.05) var ventilation: float = 0.8
@export_range(0.0, 0.9, 0.01) var maximum_cover_reduction: float = 0.55
@export_range(0.0, 100.0, 1.0) var comfortable_min: float = 35.0
@export_range(0.0, 100.0, 1.0) var comfortable_max: float = 80.0
@export_range(0.0, 100.0, 1.0) var dry_warning_threshold: float = 25.0
@export_range(0.0, 100.0, 1.0) var wet_warning_threshold: float = 90.0
@export_range(0.0, 1.0, 0.05) var stressed_production_multiplier: float = 0.25
@export_range(1, 100, 1) var ant_population_cap: int = 40
@export_range(1, 100, 1) var isopod_population_cap: int = 12
@export_range(1.0, 3600.0, 1.0) var isopod_interval_seconds: float = 240.0
@export_range(0.0, 3600.0, 1.0) var isopod_adult_age: float = 180.0
## Spent from food already eaten locally, never removed twice from a pile.
@export_range(0.1, 24.0, 0.1) var isopod_food_cost: float = 3.0
@export_range(1, 100, 1) var milestone_ant_target: int = 10
@export_range(1, 100, 1) var milestone_isopod_target: int = 3
@export_range(1.0, 3600.0, 1.0) var milestone_duration_seconds: float = 120.0
@export_range(1, 100, 1) var milestone_stored_food_minimum: int = 5

var simulation_time: float = 0.0
var isopod_time_left: float = 240.0
var ant_status := "Needs more stored food"
var isopod_status := "Needs two adults"
var reproduction_items: Array = []
var milestone_progress: float = 0.0
var milestone_complete := false
var milestone_status := "Build a supported colony"


func _ready() -> void:
	isopod_time_left = isopod_interval_seconds
	reproduction_items = preload("res://scripts/placement_catalog.gd").items()


func _physics_process(delta: float) -> void:
	if not get_parent().map_ready:
		return
	simulation_time += delta
	var cover := 0.0
	var uptake := 0.0
	for plant in get_tree().get_nodes_in_group("productive_plants"):
		if not plant.is_queued_for_deletion():
			cover += plant.soil_cover
			uptake += plant.water_uptake_per_second
	var evaporation := evaporation_per_second * ventilation * (1.0 - minf(cover, maximum_cover_reduction))
	soil_moisture = clampf(soil_moisture - (evaporation + uptake) * delta, 0.0, 100.0)
	update_reproduction(delta)
	update_milestone(delta)


func water() -> void:
	soil_moisture = clampf(soil_moisture + water_amount, 0.0, 100.0)


func comfortable() -> bool:
	return soil_moisture >= comfortable_min and soil_moisture <= comfortable_max


func production_multiplier() -> float:
	return 1.0 if comfortable() else stressed_production_multiplier


func moisture_warning() -> String:
	if soil_moisture < dry_warning_threshold:
		return "Soil too dry — water the enclosure"
	if soil_moisture > wet_warning_threshold:
		return "Soil too wet — let it dry"
	if not comfortable():
		return "Plant production slowed by soil moisture"
	return ""


func update_reproduction(delta: float) -> void:
	var world: Node = get_parent()
	var service: Node = world.get_node("SpawnService")
	var catalog: Array = reproduction_items
	var ants := get_tree().get_nodes_in_group("ants")
	for home in get_tree().get_nodes_in_group("ant_homes"):
		if ants.size() >= ant_population_cap:
			ant_status = "Population cap"
			break
		if home.stored_portions < home.worker_food_cost + home.worker_food_reserve:
			ant_status = "Needs more stored food"
			continue
		home.worker_progress = minf(home.worker_progress + delta, home.worker_interval_seconds)
		ant_status = "New worker: %ds" % ceili(home.worker_interval_seconds - home.worker_progress)
		if home.worker_progress < home.worker_interval_seconds:
			continue
		var point: Vector3 = service.find_safe_point(home.global_position, catalog[0], 3.5)
		if not point.is_finite():
			ant_status = "No safe nest exit"
			continue
		var newborn: Node3D = service.spawn_item(catalog[0], point, true)
		if newborn != null:
			home.stored_portions -= home.worker_food_cost
			home.update_food_display()
			home.food_changed.emit(home.stored_portions)
			home.worker_progress = 0.0
			world.get_node("ColonyHUD").show_notice("A new ant worker has joined the colony")
			break
	isopod_time_left = maxf(0.0, isopod_time_left - delta)
	var isopods := get_tree().get_nodes_in_group("isopods")
	if isopods.size() >= isopod_population_cap:
		isopod_status = "Population cap"
		return
	var adults: Array[Node3D] = []
	var fed: Array[Node3D] = []
	for bug in isopods:
		if bug.age_seconds >= isopod_adult_age and bug.breeding_cooldown <= 0.0:
			adults.append(bug)
			if bug.feeding_reserve >= isopod_food_cost * 0.5:
				fed.append(bug)
	if adults.size() < 2:
		isopod_status = "Needs two eligible adults"
	elif not comfortable():
		isopod_status = "Needs suitable moisture"
	elif fed.size() < 2:
		isopod_status = "Needs more food"
	elif isopod_time_left > 0.0:
		isopod_status = "Cooldown: %ds" % ceili(isopod_time_left)
	else:
		var point: Vector3 = service.find_safe_point(fed[0].global_position, catalog[1], 4.0)
		if not point.is_finite():
			isopod_status = "No safe space"
			return
		var newborn: Node3D = service.spawn_item(catalog[1], point, true)
		if newborn != null:
			for parent in [fed[0], fed[1]]:
				parent.feeding_reserve -= isopod_food_cost * 0.5
				parent.breeding_cooldown = isopod_interval_seconds
			isopod_time_left = isopod_interval_seconds
			isopod_status = "Young isopod born"
			world.get_node("ColonyHUD").show_notice("A young isopod has joined the enclosure")


func update_milestone(delta: float) -> void:
	if milestone_complete:
		milestone_status = "Milestone reached — keep the ecosystem thriving"
		return
	var ants := get_tree().get_nodes_in_group("ants")
	var isopods := get_tree().get_nodes_in_group("isopods")
	var stored := 0
	var litter := 0.0
	for home in get_tree().get_nodes_in_group("ant_homes"):
		stored += home.stored_portions
	for resource in get_tree().get_nodes_in_group("detritus_sources"):
		litter += resource.amount
	var isopods_fed := not isopods.is_empty()
	for bug in isopods:
		if bug.feeding_reserve < 0.5:
			isopods_fed = false
	if ants.size() < milestone_ant_target or isopods.size() < milestone_isopod_target:
		milestone_status = "Needs %d ants and %d isopods" % [milestone_ant_target, milestone_isopod_target]
	elif not comfortable():
		milestone_status = "Needs suitable moisture"
	elif stored < milestone_stored_food_minimum or (litter < 0.5 and not isopods_fed):
		milestone_status = "Needs a steady food supply"
	else:
		milestone_progress = minf(milestone_duration_seconds, milestone_progress + delta)
		milestone_status = "Stable ecosystem: %ds / %ds" % [floori(milestone_progress), ceili(milestone_duration_seconds)]
		if milestone_progress >= milestone_duration_seconds:
			milestone_complete = true
			get_parent().get_node("ColonyHUD").show_notice("Milestone reached! Your colony is supported. Keep playing.")
		return
	# Require a continuous period of support, rather than banking healthy seconds.
	milestone_progress = 0.0
