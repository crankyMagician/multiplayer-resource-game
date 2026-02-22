@tool
extends MultiMeshInstance3D

@export var source_mesh: Mesh
@export var count: int = 12
@export var area_size: Vector2 = Vector2(8.0, 8.0)
@export var y_offset_min: float = 0.02
@export var y_offset_max: float = 0.05
@export var min_scale: Vector3 = Vector3(0.8, 1.0, 0.8)
@export var max_scale: Vector3 = Vector3(1.3, 1.0, 1.3)
@export var max_yaw_degrees: float = 180.0
@export var scatter_seed: int = 1337

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if source_mesh == null or count <= 0:
		multimesh = null
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count
	mm.mesh = source_mesh

	var rng := RandomNumberGenerator.new()
	rng.seed = int(scatter_seed)

	for i in count:
		var px := rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var pz := rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		var py := rng.randf_range(y_offset_min, y_offset_max)
		var yaw := deg_to_rad(rng.randf_range(-max_yaw_degrees, max_yaw_degrees))
		var sx := rng.randf_range(min_scale.x, max_scale.x)
		var sy := rng.randf_range(min_scale.y, max_scale.y)
		var sz := rng.randf_range(min_scale.z, max_scale.z)

		var inst_basis := Basis(Vector3.UP, yaw).scaled(Vector3(sx, sy, sz))
		mm.set_instance_transform(i, Transform3D(inst_basis, Vector3(px, py, pz)))

	multimesh = mm
