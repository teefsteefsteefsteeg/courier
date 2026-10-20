extends SceneTree
## Phase 8 open world: builds the outlands, the scenery ground around the playable areas so
## the world never shows bare sky at its edges or between biomes:
##   res://scenes/world/chunks/outlands/outlands.tscn  one low-detail terrain mesh over the
##       whole world rect (plus a margin) with a forest of pines and broadleaf trees on it
##   res://data/world/outlands_chunks.tres             its WorldChunkSet (always loaded)
## Inside the playable areas (the village terrain mesh and Wyrmfall Vale) the outlands sink
## below the real ground, so they only show in the gaps; away from them they rise into
## wooded hills. No collision: the playable areas' own walls keep the courier in.
## Change this generator, not the scene, then re-run:
##   godot --headless --path . --script res://tools/generate_outlands.gd

const OUT := "res://scenes/world/chunks/outlands/outlands.tscn"
const CHUNK_SET := "res://data/world/outlands_chunks.tres"
const GEN := "res://assets/generated/outlands/"
const NATURE := "res://assets/models/quaternius/ultimate_nature/"
const SCATTER := preload("res://scripts/world/scatter_field.gd")
const W := preload("res://scripts/world/wyrmfall_layout.gd")
## World rect the outlands cover (the exploration rect plus a margin the camera can see).
const AREA := Rect2(-112.0, -300.0, 288.0, 410.0)
const CELL := 3.0
## Playable ground the outlands stay under: the village terrain mesh and the vale.
const PLAYABLE: Array[Rect2] = [Rect2(-80.0, -124.0, 160.0, 204.0), Rect2(-6.0, -244.0, 120.0, 120.0)]
const SINK := -1.2
const SEED := 4242
const TREES := [["PineTree_1", 3], ["PineTree_2", 3], ["PineTree_3", 3], ["PineTree_4", 2], ["CommonTree_1", 2],
		["CommonTree_2", 2], ["CommonTree_3", 2], ["BirchTree_1", 1]]

var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = SEED
	noise.seed = SEED
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	DirAccess.make_dir_recursive_absolute(GEN)
	DirAccess.make_dir_recursive_absolute(CHUNK_SET.get_base_dir())
	var root_node := Node3D.new()
	root_node.name = "outlands"
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = _mesh()
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_node.add_child(terrain)
	var forest := Node3D.new()
	forest.name = "Forest"
	root_node.add_child(forest)
	for spec in TREES:
		var field := MultiMeshInstance3D.new()
		field.set_script(SCATTER)
		field.name = String(spec[0])
		field.set(&"source", load(NATURE + String(spec[0]) + ".fbx"))
		field.set(&"transforms", _tree_transforms(int(spec[1]) * 90))
		forest.add_child(field)
	for child in root_node.find_children("*", "", true, false):
		child.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	print("%s err=%d" % [OUT, ResourceSaver.save(packed, OUT)])
	root_node.free()
	var chunk := WorldChunk.new()
	chunk.chunk_id = &"outlands"
	chunk.scene_path = OUT
	chunk.bounds = AREA
	chunk.always_loaded = true
	chunk.biome = &"outlands"
	var chunk_set := WorldChunkSet.new()
	chunk_set.biome = &"outlands"
	chunk_set.chunks.append(chunk)
	print("%s err=%d" % [CHUNK_SET, ResourceSaver.save(chunk_set, CHUNK_SET)])
	quit()


## Metres from p to the nearest playable rect (0 inside one).
func _outside(p: Vector2) -> float:
	var best := INF
	for rect in PLAYABLE:
		var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
		var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
		best = minf(best, Vector2(dx, dz).length())
	return best


## Under the playable areas: SINK. Outside them it rises over 30 m into rolling hills.
func height(p: Vector2) -> float:
	var d := _outside(p)
	if d <= 0.0:
		return SINK
	var hills := 2.5 + 6.0 * (noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5)
	return lerpf(SINK, hills, smoothstep(0.0, 30.0, d))


func _mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(AREA.size.x / CELL)
	var nz := int(AREA.size.y / CELL)
	for zi in nz:
		for xi in nx:
			var corners: Array[Vector3] = []
			for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var p := AREA.position + Vector2(xi + c.x, zi + c.y) * CELL
				corners.append(Vector3(p.x, height(p), p.y))
			# (a, b, c) with (c - a) x (b - a) pointing up is a front face in Godot.
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = corners[tri[0]]
				var b: Vector3 = corners[tri[1]]
				var c: Vector3 = corners[tri[2]]
				var normal := (b - a).cross(c - a).normalized()
				if normal.y < 0.0:
					normal = -normal
				var centre := (a + b + c) / 3.0
				var shade := noise.get_noise_2d(centre.x * 3.0, centre.z * 3.0) * 0.5 + 0.5
				var color := Color(0.25, 0.38, 0.2).lerp(Color(0.32, 0.45, 0.24), shade)
				if normal.y < 0.8:
					color = color.lerp(Color(0.42, 0.4, 0.36), 0.4)
				st.set_normal(normal)
				st.set_color(color)
				for v: Vector3 in [a, b, c]:
					st.add_vertex(v)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	mesh.surface_set_material(0, material)
	ResourceSaver.save(mesh, GEN + "outlands_terrain.res")
	return load(GEN + "outlands_terrain.res") as ArrayMesh


## Trees on the outlands only (at least 6 m outside the playable areas).
func _tree_transforms(count: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var p := Vector2(rng.randf_range(AREA.position.x, AREA.end.x), rng.randf_range(AREA.position.y, AREA.end.y))
		if _outside(p) < 6.0:
			continue
		var s := rng.randf_range(1.1, 1.8)
		out.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height(p) - 0.1, p.y)))
	return out
