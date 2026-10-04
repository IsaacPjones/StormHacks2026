extends Node

const VERSION := 1
const Production = preload("res://scripts/plant_production.gd")
const ALLOWED_SCENES := ["res://scenes/ant.tscn", "res://scenes/isopod.tscn", "res://scenes/plant.tscn", "res://scenes/nectar_plant.tscn", "res://scenes/sap_plant.tscn", "res://scenes/food.tscn", "res://scenes/scraps.tscn", "res://scenes/plant_drop.tscn"]
const ANT_FIELDS := ["starvation_seconds", "time_without_food", "age_seconds", "move_speed", "food_detection_radius", "hunger_interval", "eat_seconds", "hunger_time_left", "eat_time_left", "is_eating", "has_food", "is_harvesting", "harvest_time_left", "food_scan_time_left", "wait_time_left", "home_retry_time_left"]
const ISOPOD_FIELDS := ["starvation_seconds", "time_without_food", "age_seconds", "move_speed", "detection_range", "eating_rate", "feeding_reserve", "feeding_reserve_decay", "breeding_cooldown", "scan_time_left", "wait_time_left", "is_eating"]
const ORANGE_FIELDS := ["portions", "harvest_seconds", "gather_radius", "scraps_amount", "resource_category", "resource_kind"]
const DROP_FIELDS := ["amount", "feeding_radius", "resource_category", "resource_kind"]
const PLANT_FIELDS := ["production_enabled", "drop_radius_min", "drop_radius_max", "drop_spacing", "water_uptake_per_second", "soil_cover"]
const PROFILE_FIELDS := ["resource_category", "resource_kind", "interval_seconds", "initial_delay_seconds", "drops_per_cycle", "amount_per_drop", "max_active_drops", "harvest_seconds"]

var save_path := "user://terrarium_save.json"
var pending_load: Dictionary = {}
var pending_new := false
var next_id := 0
var last_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func id_for(node: Node) -> String:
	if not node.has_meta("save_id"):
		next_id += 1
		node.set_meta("save_id", "object_%d" % next_id)
	return String(node.get_meta("save_id"))


func vector_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func vector_from(data: Array) -> Vector3:
	return Vector3(float(data[0]), float(data[1]), float(data[2]))


func fields_for(object: Object, names: Array) -> Dictionary:
	var result := {}
	for key in names:
		var value: Variant = object.get(key)
		result[key] = String(value) if value is StringName else value
	return result


func apply_fields(object: Object, data: Dictionary, names: Array) -> void:
	for key in names:
		if not data.has(key):
			continue
		match typeof(object.get(key)):
			TYPE_INT:
				object.set(key, int(data[key]))
			TYPE_FLOAT:
				object.set(key, float(data[key]))
			TYPE_STRING_NAME:
				object.set(key, StringName(data[key]))
			_:
				object.set(key, data[key])


func profile_data(profile: Production) -> Dictionary:
	var data := fields_for(profile, PROFILE_FIELDS)
	data["color"] = [profile.placeholder_color.r, profile.placeholder_color.g, profile.placeholder_color.b, profile.placeholder_color.a]
	data["visual"] = profile.drop_visual_scene.resource_path if profile.drop_visual_scene != null else ""
	return data


func profile_from(data: Dictionary) -> Production:
	var profile := Production.new()
	apply_fields(profile, data, PROFILE_FIELDS)
	var color: Array = data.get("color", [0.95, 0.65, 0.12, 1.0])
	profile.placeholder_color = Color(color[0], color[1], color[2], color[3])
	var path: String = data.get("visual", "")
	if path.begins_with("res://") and ResourceLoader.exists(path):
		profile.drop_visual_scene = load(path) as PackedScene
	return profile


func transform_data(node: Node3D) -> Dictionary:
	return {"position": vector_data(node.global_position), "rotation": vector_data(node.global_rotation), "scale": vector_data(node.global_basis.get_scale())}


func snapshot(world: Node3D) -> Dictionary:
	var data := {"version": VERSION, "plants": [], "resources": [], "bugs": [], "homes": []}
	for plant in get_tree().get_nodes_in_group("productive_plants"):
		if plant.is_queued_for_deletion():
			continue
		var record := transform_data(plant)
		record.merge({"id": id_for(plant), "scene": plant.scene_file_path, "authored_path": "" if plant.is_in_group("dynamic_objects") else String(world.get_path_to(plant)), "fields": fields_for(plant, PLANT_FIELDS), "profiles": [], "time_left": plant.time_left.duplicate(), "placed": plant.get_meta("player_placed", false), "radius": plant.get_meta("placement_radius", 0.8), "height": plant.get_meta("placement_height", 1.2)})
		for profile in plant.productions:
			record.profiles.append(profile_data(profile) if profile != null else null)
		data.plants.append(record)
	for resource in get_tree().get_nodes_in_group("resource_sources"):
		if resource.is_queued_for_deletion():
			continue
		var record := transform_data(resource)
		var orange: bool = resource is FoodSource
		record.merge({"id": id_for(resource), "scene": resource.scene_file_path, "orange": orange, "fields": fields_for(resource, ORANGE_FIELDS if orange else DROP_FIELDS), "placed": resource.get_meta("player_placed", false), "radius": resource.get_meta("placement_radius", 0.5), "height": resource.get_meta("placement_height", 0.4)})
		if orange:
			record["linear_velocity"] = vector_data(resource.linear_velocity)
			record["angular_velocity"] = vector_data(resource.angular_velocity)
			record["sleeping"] = resource.sleeping
		else:
			record["initial_amount"] = resource.initial_amount
			if resource.has_method("take_portion"):
				record["harvest_seconds"] = resource.harvest_seconds
			var producer_ref: WeakRef = resource.get_meta("producer") if resource.has_meta("producer") else null
			var producer: Node = producer_ref.get_ref() if producer_ref != null else null
			record["producer"] = id_for(producer) if is_instance_valid(producer) else ""
			record["production_index"] = resource.get_meta("production_index", -1)
			var profile: Production = resource.get_meta("production_profile") if resource.has_meta("production_profile") else null
			if profile != null:
				record["profile"] = profile_data(profile)
		data.resources.append(record)
	for group in ["ants", "isopods"]:
		for bug in get_tree().get_nodes_in_group(group):
			if bug.is_queued_for_deletion():
				continue
			var record := transform_data(bug)
			var ant: bool = group == "ants"
			var target: Node = bug.food_target if ant else bug.resource_target
			record.merge({"id": id_for(bug), "scene": "res://scenes/ant.tscn" if ant else "res://scenes/isopod.tscn", "ant": ant, "fields": fields_for(bug, ANT_FIELDS if ant else ISOPOD_FIELDS), "target": id_for(target) if is_instance_valid(target) and not target.is_queued_for_deletion() else "", "home": String(world.get_path_to(bug.home_target)) if ant and is_instance_valid(bug.home_target) else "", "diet": [], "placed": bug.get_meta("player_placed", false)})
			for kind in bug.accepted_resource_kinds:
				record.diet.append(String(kind))
			if ant:
				record["surface"] = {"active": bug.surface_crawler.active, "normal": vector_data(bug.surface_crawler.normal), "elapsed": bug.surface_crawler.elapsed, "descending": bug.surface_crawler.descending}
			data.bugs.append(record)
	for home in get_tree().get_nodes_in_group("ant_homes"):
		data.homes.append({"path": String(world.get_path_to(home)), "stored": home.stored_portions, "worker_progress": home.worker_progress})
	var ecosystem: Node = world.get_node("Ecosystem")
	data["environment"] = {"moisture": ecosystem.soil_moisture, "time": ecosystem.simulation_time, "isopod_time_left": ecosystem.isopod_time_left, "milestone_progress": ecosystem.get("milestone_progress") if ecosystem.get("milestone_progress") != null else 0.0, "milestone_complete": ecosystem.get("milestone_complete") if ecosystem.get("milestone_complete") != null else false}
	data["speed"] = Engine.time_scale
	data["next_id"] = next_id
	return data


func save_world(world: Node3D) -> bool:
	if not world.map_ready:
		last_error = "Wait for navigation to finish preparing."
		return false
	var data := snapshot(world)
	if not valid_state(data):
		last_error = "The terrarium could not be saved safely."
		return false
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write the save slot."
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Save write failed; previous progress was kept."
		return false
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path))
	last_error = "" if error == OK else "Could not replace the save slot; previous progress was kept."
	return error == OK


func read_save() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return {}
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary and valid_state(parsed) else {}


func has_valid_save() -> bool:
	return not read_save().is_empty()


func valid_vector(data: Variant) -> bool:
	if not data is Array or data.size() != 3:
		return false
	for value in data:
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
	return true


func valid_state(data: Dictionary) -> bool:
	if data.get("version") != VERSION or not data.get("environment") is Dictionary:
		return false
	var environment: Dictionary = data.environment
	for key in ["moisture", "time", "isopod_time_left", "milestone_progress"]:
		if not (environment.get(key) is float or environment.get(key) is int) or not is_finite(float(environment[key])) or float(environment[key]) < 0.0:
			return false
	if float(environment.moisture) > 100.0 or not environment.get("milestone_complete") is bool or data.get("speed") not in [1.0, 2.0, 4.0]:
		return false
	if not (data.get("next_id") is int or data.get("next_id") is float) or float(data.next_id) < 0.0:
		return false
	var identifiers := {}
	for section in ["plants", "resources", "bugs", "homes"]:
		if not data.get(section) is Array or data[section].size() > 1000:
			return false
		for record in data[section]:
			if not record is Dictionary:
				return false
			if section == "homes":
				if not record.get("path") is String or not valid_number(record.get("stored")) or not valid_number(record.get("worker_progress")):
					return false
				continue
			if not record.get("id") is String or identifiers.has(record.id) or record.get("scene") not in ALLOWED_SCENES or not record.get("fields") is Dictionary or not record.get("placed") is bool:
				return false
			identifiers[record.id] = true
			if section != "bugs" and (not valid_number(record.get("radius")) or not valid_number(record.get("height"))):
				return false
			for key in ["position", "rotation", "scale"]:
				if not valid_vector(record.get(key)):
					return false
			for component in record.scale:
				if component <= 0.0 or component > 30.0:
					return false
			if absf(record.position[0]) > 32.0 or absf(record.position[2]) > 32.0 or absf(record.position[1]) > 30.0:
				return false
			for value in record.fields.values():
				if not (value is bool or value is String or value is float or value is int):
					return false
			if section == "plants":
				if record.scene not in ALLOWED_SCENES.slice(2, 5) or not record.get("authored_path") is String or not record.get("profiles") is Array or not record.get("time_left") is Array or record.profiles.size() != record.time_left.size():
					return false
				if not valid_fields(record.fields, PLANT_FIELDS) or record.profiles.size() > 20:
					return false
				for timer in record.time_left:
					if not valid_number(timer):
						return false
				for profile in record.profiles:
					if profile != null and not valid_profile(profile):
						return false
			elif section == "bugs":
				if record.scene not in ALLOWED_SCENES.slice(0, 2) or not record.get("ant") is bool or not record.get("target") is String or not record.get("home") is String or not record.get("diet") is Array:
					return false
				if record.ant != (record.scene == "res://scenes/ant.tscn") or not valid_fields(record.fields, ANT_FIELDS if record.ant else ISOPOD_FIELDS):
					return false
				for kind in record.diet:
					if not kind is String:
						return false
				if record.ant and (not record.get("surface") is Dictionary or not record.surface.get("active") is bool or not valid_vector(record.surface.get("normal")) or not valid_number(record.surface.get("elapsed")) or not record.surface.get("descending") is bool):
					return false
				if record.ant and not is_equal_approx(vector_from(record.surface.normal).length(), 1.0):
					return false
			elif section == "resources":
				if record.scene not in ALLOWED_SCENES.slice(5) or not record.get("orange") is bool:
					return false
				if record.orange != (record.scene == "res://scenes/food.tscn") or not valid_fields(record.fields, ORANGE_FIELDS if record.orange else DROP_FIELDS):
					return false
				if record.orange:
					if not valid_vector(record.get("linear_velocity")) or not valid_vector(record.get("angular_velocity")) or not record.get("sleeping") is bool or float(record.fields.get("portions", 0)) <= 0.0:
						return false
				elif float(record.fields.get("amount", 0)) <= 0.0 or not valid_number(record.get("initial_amount")) or (record.has("profile") and not valid_profile(record.profile)):
					return false
	return true


func valid_profile(data: Variant) -> bool:
	if not data is Dictionary or not data.get("color") is Array or data.color.size() != 4 or not data.get("visual") is String:
		return false
	for key in PROFILE_FIELDS:
		if key == "resource_kind":
			if not data.get(key) is String:
				return false
		elif not valid_number(data.get(key), -1.0 if key == "initial_delay_seconds" else 0.0):
			return false
	for value in data.color:
		if not valid_number(value):
			return false
	if int(data.resource_category) not in [0, 1, 2] or data.interval_seconds <= 0.0 or data.amount_per_drop <= 0.0 or data.max_active_drops < 1 or data.drops_per_cycle < 1:
		return false
	return true


func valid_number(value: Variant, minimum: float = 0.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) < 1.0e9


func valid_fields(data: Dictionary, names: Array) -> bool:
	for key in names:
		# Older slots predate starvation; use each scene's forgiving defaults.
		if key in ["starvation_seconds", "time_without_food"] and not data.has(key):
			continue
		if key in ["has_food", "is_harvesting", "is_eating", "production_enabled"]:
			if not data.get(key) is bool:
				return false
		elif key == "resource_kind":
			if not data.get(key) is String:
				return false
		elif not valid_number(data.get(key)):
			return false
	return true


func restore_transform(node: Node3D, record: Dictionary) -> void:
	node.global_position = vector_from(record.position)
	node.global_rotation = vector_from(record.rotation)
	node.scale = vector_from(record.scale)
	node.set_meta("save_id", record.id)
	node.set_meta("player_placed", record.placed)
	node.set_meta("placement_radius", record.get("radius", 0.5))
	node.set_meta("placement_height", record.get("height", 0.7))


func apply_state(world: Node3D, data: Dictionary) -> void:
	# The authored map and decorative models remain instantiated from main.tscn.
	# Replace only creatures/resources and player-created plants.
	for node in get_tree().get_nodes_in_group("ants") + get_tree().get_nodes_in_group("isopods") + get_tree().get_nodes_in_group("resource_sources"):
		node.get_parent().remove_child(node)
		node.queue_free()
	for plant in get_tree().get_nodes_in_group("productive_plants"):
		if plant.is_in_group("dynamic_objects"):
			plant.get_parent().remove_child(plant)
			plant.queue_free()
	var objects := {}
	for record in data.plants:
		var plant: Node3D = world.get_node_or_null(record.authored_path) if not record.authored_path.is_empty() else null
		if plant == null:
			if not record.authored_path.is_empty():
				continue
			plant = (load(record.scene) as PackedScene).instantiate()
			world.get_node("NavigationRegion3D").add_child(plant)
			plant.add_to_group("dynamic_objects")
			world.get_node("SpawnService").add_pick_area(plant, record.radius, record.height)
			world.get_node("SpawnService").add_plant_collision(plant, record.radius, record.height)
		elif not plant.is_in_group("productive_plants"):
			continue
		apply_fields(plant, record.fields, PLANT_FIELDS)
		restore_transform(plant, record)
		plant.productions.clear()
		for profile in record.profiles:
			plant.productions.append(profile_from(profile) if profile != null else null)
		plant.time_left.assign(record.time_left)
		plant.active_drops.clear()
		objects[record.id] = plant
	for record in data.resources:
		var resource: Node3D = (load(record.scene) as PackedScene).instantiate()
		apply_fields(resource, record.fields, ORANGE_FIELDS if record.orange else DROP_FIELDS)
		if record.has("harvest_seconds"):
			resource.set("harvest_seconds", record.harvest_seconds)
		if record.has("profile"):
			var profile := profile_from(record.profile)
			apply_resource_visual(resource, profile)
			resource.set_meta("production_profile", profile)
		world.add_child(resource)
		restore_transform(resource, record)
		if record.placed:
			resource.add_to_group("dynamic_objects")
			world.get_node("SpawnService").add_pick_area(resource, record.radius, record.height)
		if record.orange:
			resource.linear_velocity = vector_from(record.linear_velocity)
			resource.angular_velocity = vector_from(record.angular_velocity)
			resource.sleeping = record.sleeping
		else:
			resource.initial_amount = maxf(resource.amount, float(record.get("initial_amount", resource.amount)))
			resource.update_visual()
			var producer: Node = objects.get(record.get("producer", ""))
			if producer != null:
				var index := int(record.production_index)
				resource.set_meta("producer", weakref(producer))
				resource.set_meta("production_index", index)
				producer.active_drops.append({"index": index, "reference": weakref(resource)})
		objects[record.id] = resource
	for record in data.bugs:
		var bug: Node3D = (load(record.scene) as PackedScene).instantiate()
		world.add_child(bug)
		bug.add_to_group("dynamic_objects")
		bug.set_physics_process(false)
		restore_transform(bug, record)
		apply_fields(bug, record.fields, ANT_FIELDS if record.ant else ISOPOD_FIELDS)
		bug.accepted_resource_kinds.clear()
		for kind in record.diet:
			bug.accepted_resource_kinds.append(StringName(kind))
		bug.wander_limit = world.exploration_limit
		if record.ant:
			bug.food_target = objects.get(record.target)
			bug.home_target = world.get_node_or_null(record.home) if not record.home.is_empty() else null
			bug.carried_food.visible = bug.has_food
			bug.surface_crawler.active = record.surface.active
			bug.surface_crawler.normal = vector_from(record.surface.normal).normalized()
			bug.surface_crawler.elapsed = float(record.surface.elapsed)
			bug.surface_crawler.descending = record.surface.descending
			bug.up_direction = bug.surface_crawler.normal if record.surface.active else Vector3.UP
		else:
			bug.resource_target = objects.get(record.target)
	for record in data.homes:
		var home: Node = world.get_node_or_null(record.path)
		if home != null and home.is_in_group("ant_homes"):
			home.stored_portions = int(record.stored)
			home.worker_progress = float(record.worker_progress)
			home.update_food_display()
	var environment: Dictionary = data.environment
	var ecosystem: Node = world.get_node("Ecosystem")
	ecosystem.soil_moisture = float(environment.moisture)
	ecosystem.simulation_time = float(environment.time)
	ecosystem.isopod_time_left = float(environment.isopod_time_left)
	if ecosystem.get("milestone_progress") != null:
		ecosystem.set("milestone_progress", float(environment.milestone_progress))
		ecosystem.set("milestone_complete", environment.milestone_complete)
	Engine.time_scale = float(data.speed)
	next_id = int(data.get("next_id", next_id))


func apply_resource_visual(resource: Node3D, profile: Production) -> void:
	var visual: Node3D = resource.get_node("Visual")
	if profile.drop_visual_scene != null:
		for child in visual.get_children():
			visual.remove_child(child)
			child.queue_free()
		visual.add_child(profile.drop_visual_scene.instantiate())
	else:
		var mesh: MeshInstance3D = visual.get_node_or_null("Placeholder")
		if mesh != null:
			var material := StandardMaterial3D.new()
			material.albedo_color = profile.placeholder_color
			mesh.material_override = material
