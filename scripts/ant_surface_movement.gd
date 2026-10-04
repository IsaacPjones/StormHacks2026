extends RefCounted

var active := false
var normal := Vector3.UP
var elapsed := 0.0
var descending := false
var walk_direction := Vector3.UP


func climbable(collider: Object) -> bool:
	if not collider is Node or collider is RigidBody3D:
		return false
	var node: Node = collider
	while node != null:
		if node.is_in_group("glass_surface") or "glass" in node.name.to_lower():
			return false
		node = node.get_parent()
	return collider is StaticBody3D or collider is CSGShape3D or collider.is_in_group("placement_ground")


func ray(actor: CharacterBody3D, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, end, 1)
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_ray(query)


func aligned_basis(direction: Vector3, surface_normal: Vector3, scale: Vector3) -> Basis:
	var tangent := direction.slide(surface_normal).normalized()
	if tangent.length_squared() < 0.01:
		tangent = Vector3.FORWARD.slide(surface_normal).normalized()
	return Basis.looking_at(tangent, surface_normal).scaled(scale)


func reset(actor: CharacterBody3D) -> void:
	active = false
	normal = Vector3.UP
	elapsed = 0.0
	descending = false
	actor.up_direction = Vector3.UP
	var forward := -actor.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	actor.global_basis = aligned_basis(forward, Vector3.UP, actor.global_basis.get_scale())
	actor.velocity.y = 0.0
	actor.navigation_ready = false


func attach(actor: CharacterBody3D, hit: Dictionary, descend: bool = false) -> bool:
	if hit.is_empty() or not climbable(hit.collider) or absf(hit.normal.dot(Vector3.UP)) > 0.6:
		return false
	var wall_normal: Vector3 = hit.normal.normalized()
	var direction := Vector3.DOWN if descend else Vector3.UP
	var basis := aligned_basis(direction, wall_normal, actor.global_basis.get_scale())
	# Sweep up/out before rotating the body; do not teleport through a wall.
	var lift := Vector3.UP * 0.65 + (wall_normal * 0.7 if descend else Vector3.ZERO)
	if actor.test_move(actor.global_transform, lift):
		return false
	var anchor: Vector3 = hit.position + wall_normal * 0.08 + (Vector3.ZERO if descend else Vector3.UP * 0.5)
	var lifted := Transform3D(basis, actor.global_position + lift)
	if actor.test_move(lifted, anchor - lifted.origin):
		return false
	actor.global_transform = Transform3D(basis, anchor)
	actor.up_direction = wall_normal
	active = true
	normal = wall_normal
	elapsed = 0.0
	descending = descend
	walk_direction = direction.slide(normal).normalized()
	return true


func before_move(actor: CharacterBody3D, delta: float) -> void:
	if not actor.wall_crawling_enabled:
		if active:
			reset(actor)
		return
	if not active:
		var motion := Vector3(actor.velocity.x, 0.0, actor.velocity.z)
		if motion.length() < 0.05 or not actor.is_on_floor():
			return
		var direction := motion.normalized()
		var hit := ray(actor, actor.global_position + Vector3.UP * 0.3, actor.global_position + Vector3.UP * 0.3 + direction * actor.wall_probe_distance)
		if not hit.is_empty() and absf(hit.normal.dot(Vector3.UP)) < 0.6 and hit.normal.dot(direction) < -0.2:
			attach(actor, hit)
		else:
			# Leave an isolated rock/tree top by gripping its outer face.
			var ahead := actor.global_position + direction * 0.8
			var below := ray(actor, ahead + Vector3.UP * 0.3, ahead + Vector3.DOWN * 1.1)
			if below.is_empty() or below.position.y < actor.global_position.y - 0.8:
				var side := ray(actor, ahead + Vector3.DOWN * 0.3, ahead + Vector3.DOWN * 0.3 - direction * 1.2)
				if not side.is_empty():
					attach(actor, side, true)
	if not active:
		return
	elapsed += delta
	if elapsed > actor.wall_visit_seconds:
		descending = true
	var support := ray(actor, actor.global_position + normal * 0.65, actor.global_position - normal * 0.35)
	if support.is_empty() or not climbable(support.collider):
		if try_landing(actor):
			return
		reset(actor)
		return
	var next_normal: Vector3 = support.normal.normalized()
	if next_normal.dot(Vector3.UP) > 0.75:
		reset(actor)
		return
	if next_normal.dot(Vector3.UP) < -0.4:
		# Turn back rather than walk along ceilings or into an overhang.
		descending = true
	else:
		normal = next_normal
	walk_direction = (Vector3.DOWN if descending else Vector3.UP).slide(normal).normalized()
	if walk_direction.length_squared() < 0.01:
		reset(actor)
		return
	actor.up_direction = normal
	actor.global_basis = aligned_basis(walk_direction, normal, actor.global_basis.get_scale())
	actor.velocity = walk_direction * actor.wall_crawl_speed - normal * actor.wall_adhesion_speed
	if descending:
		var ground := ray(actor, actor.global_position + normal * 0.4, actor.global_position + normal * 0.4 + Vector3.DOWN * 0.7)
		if not ground.is_empty() and ground.normal.y > 0.75 and ground.position.y > actor.global_position.y - 0.55:
			reset(actor)
			actor.global_position.y = maxf(actor.global_position.y, ground.position.y + 0.1)


func try_landing(actor: CharacterBody3D) -> bool:
	var forward := -normal
	var start := actor.global_position + Vector3.UP * 0.7 + forward * 0.7
	var hit := ray(actor, start, start + Vector3.DOWN * 1.5)
	if hit.is_empty() or not climbable(hit.collider) or hit.normal.y < 0.75:
		return false
	var basis := aligned_basis(forward, Vector3.UP, actor.global_basis.get_scale())
	var point: Vector3 = hit.position + Vector3.UP * 0.1
	if actor.test_move(Transform3D(basis, actor.global_position), point - actor.global_position):
		return false
	actor.global_transform = Transform3D(basis, point)
	reset(actor)
	return true
