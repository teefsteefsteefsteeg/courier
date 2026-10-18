class_name VillageTerrain
extends MeshInstance3D
## Visual ground for the village: a grid mesh that is perfectly flat (y = 0)
## across the walkable area and rises into gentle hills beyond the boundary
## walls, so the village sits in a valley instead of on a floating plane.
## Gameplay collision is unchanged (the flat Ground body and Boundary walls).
## Optionally scatters a tree line over the hills.

@export var ground_material: Material
## Half-size of the generated square, metres.
@export var extent: float = 80.0
@export var cell_size: float = 1.0
## Distance (square metric, max(|x|, |z|)) from the centre where hills start and peak.
@export var hill_start: float = 45.0
@export var hill_full: float = 60.0
@export var hill_height: float = 5.0
@export var hill_seed: int = 9
@export_group("Hill trees")
@export var tree_scenes: Array[PackedScene] = []
@export var tree_count: int = 0
@export var tree_seed: int = 31

var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = hill_seed
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	mesh = _build_mesh()
	if ground_material != null:
		material_override = ground_material
	_scatter_trees()


## Terrain height at a world XZ position (0 inside the village).
func height_at(x: float, z: float) -> float:
	var d := _square_distance(x, z)
	var rise := smoothstep(hill_start, hill_full, d)
	if rise <= 0.0:
		return 0.0
	return rise * hill_height * (0.6 + 0.8 * (_noise.get_noise_2d(x, z) * 0.5 + 0.5))


static func _square_distance(x: float, z: float) -> float:
	# Square metric, so the whole walkable square inside the walls stays flat;
	# the height noise breaks up the straight edges of the hills.
	return maxf(absf(x), absf(z))


func _build_mesh() -> ArrayMesh:
	var steps := int(round(extent * 2.0 / cell_size))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in steps + 1:
		for i in steps + 1:
			var x := -extent + i * cell_size
			var z := -extent + j * cell_size
			var h := height_at(x, z)
			verts.append(Vector3(x, h, z))
			var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
			var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			uvs.append(Vector2(x, z))
	var row := steps + 1
	for j in steps:
		for i in steps:
			var a := j * row + i
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _scatter_trees() -> void:
	if tree_scenes.is_empty() or tree_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var holder := Node3D.new()
	holder.name = "HillTrees"
	add_child(holder)
	var placed := 0
	var tries := 0
	while placed < tree_count and tries < tree_count * 20:
		tries += 1
		var x := rng.randf_range(-extent + 6.0, extent - 6.0)
		var z := rng.randf_range(-extent + 6.0, extent - 6.0)
		var d := _square_distance(x, z)
		if d < hill_start + 1.5 or d > hill_full + 8.0:
			continue
		var tree := tree_scenes[rng.randi() % tree_scenes.size()].instantiate() as Node3D
		tree.position = Vector3(x, height_at(x, z) - 0.15, z)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(1.0, 1.5)
		holder.add_child(tree)
		placed += 1
