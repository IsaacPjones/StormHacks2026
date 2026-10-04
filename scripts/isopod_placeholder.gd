extends Node3D


func _ready() -> void:
	# All placeholder geometry lives under Visual. Replace this node with the
	# final model without changing the creature's collision or feeding logic.
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.31, 0.34, 0.32)
	shell.roughness = 0.85
	var legs := StandardMaterial3D.new()
	legs.albedo_color = Color(0.16, 0.18, 0.15)
	var eyes := StandardMaterial3D.new()
	eyes.albedo_color = Color(0.025, 0.02, 0.015)
	for index in range(7):
		var z: float = (index - 3) * 0.16
		var width: float = 0.8 + 0.18 * sin(float(index) / 6.0 * PI)
		add_ellipsoid(Vector3(0, 0.24, z), Vector3(width, 0.42, 0.34), shell)
		for side in [-1.0, 1.0]:
			var leg := add_ellipsoid(Vector3(side * 0.36, 0.1, z + 0.025), Vector3(0.35, 0.06, 0.1), legs)
			leg.rotation.y = side * 0.35
	add_ellipsoid(Vector3(0, 0.2, -0.62), Vector3(0.5, 0.3, 0.3), shell)
	for side in [-1.0, 1.0]:
		add_ellipsoid(Vector3(side * 0.17, 0.25, -0.75), Vector3(0.055, 0.055, 0.055), eyes)
		var antenna := add_ellipsoid(Vector3(side * 0.2, 0.16, -0.93), Vector3(0.04, 0.04, 0.36), legs)
		antenna.rotation.y = -side * 0.4


func add_ellipsoid(position_value: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = material
	instance.mesh = sphere
	instance.position = position_value
	instance.scale = size
	add_child(instance)
	return instance
