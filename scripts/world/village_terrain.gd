class_name VillageTerrain
extends MeshInstance3D
## Visual ground for the village: a grid mesh that is perfectly flat (y = 0)
## across the walkable area and rises into gentle hills beyond the boundary
## walls, so the village sits in a valley instead of on a floating plane.
## Gameplay collision is unchanged (the flat Ground body and Boundary walls).
## Optionally scatters a tree line over the hills.

@export var ground_material: Material
## Half-size of the generated square, metres (used when mesh_rect is empty).
@export var extent: float = 80.0
## World XZ area the mesh covers (Phase 7: the village plus the Whisperwood annex). Empty =
## the square of half-size extent.
@export var mesh_rect: Rect2 = Rect2()
@export var cell_size: float = 1.0
## Walkable areas kept perfectly flat. Hills rise with the square-metric distance outside them.
## Empty = the original village square (|x|, |z| <= 44).
@export var flat_rects: Array[Rect2] = []
## Distance (square metric, max(|x|, |z|)) from the centre where hills start and peak, for the
## original square; with flat_rects they apply as the distance outside the walkable area + 44.
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
	var d := _hill_distance(x, z)
	var rise := smoothstep(hill_start, hill_full, d)
	if rise <= 0.0:
		return 0.0
	return rise * hill_height * (0.6 + 0.8 * (_noise.get_noise_2d(x, z) * 0.5 + 0.5))


static func _square_distance(x: float, z: float) -> float:
	# Square metric, so the whole walkable square inside the walls stays flat;
	# the height noise breaks up the straight edges of the hills.
	return maxf(absf(x), absf(z))


## Square-metric distance used for the hills: max(|x|, |z|) for the original square, or the
## distance outside the nearest walkable rect + 44 (the same scale) with flat_rects.
func _hill_distance(x: float, z: float) -> float:
	if flat_rects.is_empty():
		return _square_distance(x, z)
	var best := INF
	for rect in flat_rects:
		var dx := maxf(maxf(rect.position.x - x, x - rect.end.x), 0.0)
		var dz := maxf(maxf(rect.position.y - z, z - rect.end.y), 0.0)
		best = minf(best, maxf(dx, dz))
	return best + 44.0


func _mesh_area() -> Rect2:
	return mesh_rect if mesh_rect.has_area() else Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


func _build_mesh() -> ArrayMesh:
	var area := _mesh_area()
	var steps_x := int(round(area.size.x / cell_size))
	var steps_z := int(round(area.size.y / cell_size))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in steps_z + 1:
		for i in steps_x + 1:
			var x := area.position.x + i * cell_size
			var z := area.position.y + j * cell_size
			var h := height_at(x, z)
			verts.append(Vector3(x, h, z))
			var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
			var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			uvs.append(Vector2(x, z))
	var row := steps_x + 1
	for j in steps_z:
		for i in steps_x:
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
	var area := _mesh_area()
	while placed < tree_count and tries < tree_count * 20:
		tries += 1
		var x := rng.randf_range(area.position.x + 6.0, area.end.x - 6.0)
		var z := rng.randf_range(area.position.y + 6.0, area.end.y - 6.0)
		var d := _hill_distance(x, z)
		if d < hill_start + 1.5 or d > hill_full + 8.0:
			continue
		var tree := tree_scenes[rng.randi() % tree_scenes.size()].instantiate() as Node3D
		tree.position = Vector3(x, height_at(x, z) - 0.15, z)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(1.0, 1.5)
		holder.add_child(tree)
		placed += 1
