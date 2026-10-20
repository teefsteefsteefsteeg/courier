extends SceneTree
## Phase 8: builds Wyrmfall Vale from scripts/world/wyrmfall_layout.gd as part of the one
## continuous open world (no gate, no region scene): the vale lies north of the Whisperwood,
## its origin at WyrmfallLayout.WORLD_ORIGIN, and the forest trail walks into it through a
## pass in its southern hills. The vale is built whole in vale space, then cut into
## streamable chunks (WorldStreamer):
##   res://scenes/world/chunks/wyrmfall/wyrmfall_<x>_<z>.tscn  four 60 x 60 m tiles: terrain
##       tile (mesh and HeightMapShape3D, skirted at the vale's outer edge) and everything
##       standing on it (trees, rocks, props, undergrowth instances, camp and ruin pieces,
##       lamps, tool sites, creatures)
##   res://scenes/world/chunks/wyrmfall/wyrmfall_core.tscn    water, waterfall, walls and the
##       bridge, kept whole so the river never breaks at a tile edge
##   res://scenes/world/chunks/wyrmfall/wyrmfall_places.tscn  the vale's WorldLocations (always
##       loaded, for the map and discovery)
##   res://data/world/wyrmfall_chunks.tres                    the WorldChunkSet listing them
##   res://assets/generated/wyrmfall/          terrain tiles and height collision, newmap
##                                             meshes (with opaque materials), the map image
## Contents of the region:
##   Terrain       flat-shaded height field (vertex colours: grass, road, banks, cliff rock)
##                 and a HeightMapShape3D of the same samples
##   Water         the Falls Pool, the Wyrm River and the plateau stream (water_kit lake
##                 shader), the waterfall sheet (assets/shaders/waterfall.gdshader), mist
##                 and spray at the plunge; RiverWater nodes and two FishingSpots for the rod
##   Walls         invisible walls: boundary, cliff foot, pool rim and both river banks (open
##                 where the Old Stone Bridge crosses)
##   Bridge        newmap Bridge01 with its own mesh as collision
##   Camp, Ruins   newmap pack (FreeVersion AllAssets): fisher's hut, stall, barrels, lamps;
##                 broken stone walls and a giant dead trunk
##   Trees, Props  Quaternius ultimate_nature trees (trunk colliders, CameraOccluder), rocks,
##                 undergrowth (ScatterField)
##   ToolSites     two trees, two ore rocks and soft soil (region-prefixed target ids)
##   Creatures     forest slimes on the far bank
##   Pass, Places  the pass from the Whisperwood (signpost), Arrival marker, WorldLocations
## Change this generator, not the scenes:
##   godot --headless --path . --script res://tools/generate_wyrmfall.gd

const L := preload("res://scripts/world/wyrmfall_layout.gd")
const CHUNK_DIR := "res://scenes/world/chunks/wyrmfall/"
const CHUNK_SET := "res://data/world/wyrmfall_chunks.tres"
## Tile edge (m): the vale (2 x HALF across) is cut into 2 x 2 tiles.
const TILE := 60
## Kept whole in the core chunk / always-loaded places chunk.
const CORE_NODES := ["Water", "Waterfall", "Walls", "OldStoneBridge"]
const PLACE_NODES := ["Locations", "Spawns"]
const GEN := "res://assets/generated/wyrmfall/"
const NEWMAP := "res://assets/newmap/FreeVersion/AllModelsInOne/AllAssets_with_texture.glb"
const NATURE := "res://assets/models/quaternius/ultimate_nature/"
const INTERACTABLE := preload("res://scripts/interaction/interactable.gd")
const LOCATION := preload("res://scripts/world/world_location.gd")
const OCCLUDER := preload("res://scripts/world/camera_occluder.gd")
const SCATTER := preload("res://scripts/world/scatter_field.gd")
const RIVER_WATER := preload("res://scripts/world/river_water.gd")
const FISHING_SPOT := preload("res://scripts/tools/fishing_spot.gd")
const WATER_PRESET := "res://assets/vfx/water_kit/presets/pond_toon.tres"
const WATERFALL_SHADER := "res://assets/shaders/waterfall.gdshader"
const GATE_MODEL := "res://scenes/generated/wayfarer_open_gate.tscn"
const SIGNPOST := "res://scenes/props/signpost.tscn"
const SLIME := "res://scenes/gameplay/combat/forest_slime.tscn"
const TOOL_TREE := "res://scenes/world/tools/harvest_tree.tscn"
const TOOL_ROCK := "res://scenes/world/tools/ore_rock.tscn"
const TOOL_SOIL := "res://scenes/world/tools/dig_spot.tscn"
const FISH := ["res://data/materials/pond_perch.tres", "res://data/materials/silver_trout.tres", "res://data/materials/golden_carp.tres"]
const ROCKS := ["res://scenes/props/nature/rock_moss_2.tscn", "res://scenes/props/nature/rock_2.tscn", "res://scenes/props/nature/rock_3.tscn"]

## Where the village's gate stands (south edge of Willowmere) and its passage direction.

## model, weight, scale min, scale max, trunk radius
const TREES := [
	["CommonTree_1", 4, 1.1, 1.5, 0.35], ["CommonTree_2", 4, 1.1, 1.5, 0.35], ["CommonTree_3", 4, 1.1, 1.5, 0.35],
	["CommonTree_4", 3, 1.1, 1.5, 0.35], ["CommonTree_5", 3, 1.1, 1.5, 0.35],
	["PineTree_1", 3, 1.2, 1.6, 0.35], ["PineTree_2", 3, 1.2, 1.6, 0.35], ["PineTree_3", 2, 1.2, 1.6, 0.35],
	["BirchTree_1", 3, 1.1, 1.4, 0.25], ["BirchTree_2", 3, 1.1, 1.4, 0.25],
	["CommonTree_Autumn_1", 2, 1.1, 1.4, 0.35], ["BirchTree_Autumn_1", 2, 1.1, 1.4, 0.25],
]
const WATERSIDE_TREES := [["Willow_1", 0.9, 1.1, 0.4], ["Willow_2", 0.9, 1.1, 0.4], ["Willow_3", 0.9, 1.1, 0.4]]
const PLATEAU_TREES := ["PineTree_1", "PineTree_2", "PineTree_3", "PineTree_4", "PineTree_5"]
const CAMERA_DIR := Vector2(0.7071, 0.7071)
## The newmap models the vale places.
const NEWMAP_USED := ["Bridge01", "Stylized_Hut01", "Market03", "Barrel01", "Barrel03", "Box01", "Bench01", "Brazier",
		"Ladder", "Wheel_L", "ClayVase01", "ClayVase03", "FenceWood_H01", "Streetlamp01", "Wall_Stone01", "Wall_Stone02",
		"Wall_Stone03", "Wall_Stone04", "Wall_Stone05", "Trunk02", "Trunk04", "RockMedium", "RockSmall", "Foliage01"]
const BAKED_TEXTURE_SIZE := 512

var rng := RandomNumberGenerator.new()
var root_node: Node3D
var heights := PackedFloat32Array()
## [Vector2 centre, radius] of things already standing.
var obstacles: Array = []
var _cache := {}
var _newmap := {}
## Tree positions, for the map.
var tree_points: Array[Vector2] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rng.seed = L.SEED
	DirAccess.make_dir_recursive_absolute(GEN + "newmap")
	DirAccess.make_dir_recursive_absolute(CHUNK_DIR)
	DirAccess.make_dir_recursive_absolute(CHUNK_SET.get_base_dir())
	_sample_heights()
	_extract_newmap()

	root_node = Node3D.new()
	root_node.name = "WyrmfallVale"
	_terrain()
	_water()
	_waterfall()
	_walls()
	_bridge()
	_camp()
	_ruins()
	_pass()
	_tool_sites()
	_locations()
	_creatures()
	_cliff_rocks()
	_trees()
	_props()
	_undergrowth()
	print("wyrmfall: %d trees, %d obstacles" % [root_node.get_node("Trees").get_child_count(), obstacles.size()])
	_split_and_save()
	root_node.free()
	_map_image()
	quit()


func _save(node: Node, path: String) -> void:
	for child in node.find_children("*", "", true, false):
		if child.owner == null:
			child.owner = node
	var packed := PackedScene.new()
	packed.pack(node)
	var err := ResourceSaver.save(packed, path)
	print("saved %s err=%d" % [path, err])


# --- heights -------------------------------------------------------------------

func _sample_heights() -> void:
	heights.resize(L.GRID * L.GRID)
	for zi in L.GRID:
		for xi in L.GRID:
			heights[zi * L.GRID + xi] = L.height(xi - L.HALF, zi - L.HALF)


func _h(xi: int, zi: int) -> float:
	return heights[clampi(zi, 0, L.GRID - 1) * L.GRID + clampi(xi, 0, L.GRID - 1)]


## Height of the triangulated surface (what the HeightMapShape3D collides with).
func surface_y(x: float, z: float) -> float:
	var fx := x + L.HALF
	var fz := z + L.HALF
	var xi := floori(fx)
	var zi := floori(fz)
	var u := fx - xi
	var v := fz - zi
	var a := _h(xi, zi)
	var b := _h(xi + 1, zi)
	var c := _h(xi, zi + 1)
	var d := _h(xi + 1, zi + 1)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func _at(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, surface_y(p.x, p.y) + lift, p.y)


# --- newmap pack ---------------------------------------------------------------

## Saves each newmap model the vale uses as its own mesh (materials made opaque, foliage
## alpha-scissored). The raw pack is not committed, so its textures are baked into the
## meshes' folder too (downscaled, lossy WebP in PortableCompressedTexture2D resources, no
## import step; normal maps dropped): the region needs nothing from assets/newmap/.
func _extract_newmap() -> void:
	var pack := (load(NEWMAP) as PackedScene).instantiate()
	for child in pack.get_children():
		var source := child as MeshInstance3D
		var key := String(child.name).replace(" ", "_")
		if source == null or source.mesh == null or not key in NEWMAP_USED:
			continue
		var mesh := source.mesh.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL) as Mesh
		for surface in mesh.get_surface_count():
			var original := mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null:
				continue
			var material := original.duplicate() as BaseMaterial3D
			mesh.surface_set_material(surface, material)
			material.albedo_texture = _baked_texture(material.albedo_texture)
			material.emission_texture = _baked_texture(material.emission_texture)
			material.normal_enabled = false
			material.normal_texture = null
			for texture_param in [BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
				material.set_texture(texture_param, null)
			material.ao_enabled = false
			if key.begins_with("Foliage") or material.resource_name.to_lower().contains("foliage"):
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.4
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
			else:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		var path := GEN + "newmap/" + key + ".res"
		ResourceSaver.save(mesh, path)
		_newmap[key] = path
	pack.free()


## A self-contained copy of a pack texture (cached by source path); null stays null.
func _baked_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key := "baked:" + texture.resource_path
	if _cache.has(key):
		return _cache[key]
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	if image.get_width() > BAKED_TEXTURE_SIZE:
		image.resize(BAKED_TEXTURE_SIZE, BAKED_TEXTURE_SIZE * image.get_height() / image.get_width(), Image.INTERPOLATE_LANCZOS)
	var baked := PortableCompressedTexture2D.new()
	# Otherwise the compressed data is dropped after upload and the saved file is empty.
	baked.keep_compressed_buffer = true
	baked.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, 0.85)
	var name := texture.resource_path.get_file().get_basename().replace("AllAssets_with_texture_", "").replace(" ", "_")
	var path := GEN + "newmap/tex_" + name + ".res"
	ResourceSaver.save(baked, path)
	var loaded := load(path) as Texture2D
	_cache[key] = loaded
	return loaded


func _newmap_mesh(key: String) -> Mesh:
	return _load(_newmap[key]) as Mesh


## A newmap model standing at p (ground height), turned by yaw; collider: a box from its
## bounds (shrunk by box_scale), none when box_scale is 0.
func _newmap_prop(parent: Node, node_name: String, key: String, p: Vector2, yaw: float, scale: float = 1.0, box_scale: float = 0.9, sink: float = 0.0) -> Node3D:
	var mesh := _newmap_mesh(key)
	var body: Node3D = StaticBody3D.new() if box_scale > 0.0 else Node3D.new()
	body.name = node_name
	body.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), _at(p, -sink))
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = mesh
	body.add_child(model)
	if box_scale > 0.0:
		var aabb := mesh.get_aabb()
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		var box := BoxShape3D.new()
		box.size = Vector3(aabb.size.x * box_scale, maxf(aabb.size.y, 1.2), aabb.size.z * box_scale)
		shape.shape = box
		shape.position = aabb.get_center() * Vector3(1, 0, 1) + Vector3.UP * box.size.y * 0.5
		body.add_child(shape)
		var radius := Vector2(aabb.size.x, aabb.size.z).length() * 0.5 * scale
		obstacles.append([p, radius])
	parent.add_child(body)
	return body


# --- environment ---------------------------------------------------------------

# --- terrain -------------------------------------------------------------------

## The terrain as TILE x TILE m tiles (mesh and HeightMapShape3D each, same samples and the
## same triangle split as the collision), skirted down where a tile meets the vale's outer
## edge so the edge reads as solid ground from the neighbouring biome.
func _terrain() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	var tiles := (L.GRID - 1) / TILE
	for tz in tiles:
		for tx in tiles:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for zi in range(tz * TILE, (tz + 1) * TILE):
				for xi in range(tx * TILE, (tx + 1) * TILE):
					var p00 := Vector3(xi - L.HALF, _h(xi, zi), zi - L.HALF)
					var p10 := Vector3(xi + 1 - L.HALF, _h(xi + 1, zi), zi - L.HALF)
					var p01 := Vector3(xi - L.HALF, _h(xi, zi + 1), zi + 1 - L.HALF)
					var p11 := Vector3(xi + 1 - L.HALF, _h(xi + 1, zi + 1), zi + 1 - L.HALF)
					# Same split as HeightMapShape3D (p00-p11 diagonal).
					_triangle(st, p00, p10, p11)
					_triangle(st, p00, p11, p01)
			_skirts(st, tx, tz, tiles)
			var mesh := st.commit()
			mesh.surface_set_material(0, material)
			var mesh_path := GEN + "terrain_%d_%d.res" % [tx, tz]
			ResourceSaver.save(mesh, mesh_path)
			var terrain := MeshInstance3D.new()
			terrain.name = "Terrain_%d_%d" % [tx, tz]
			terrain.mesh = load(mesh_path)
			root_node.add_child(terrain)
			var data := PackedFloat32Array()
			for zi in range(tz * TILE, (tz + 1) * TILE + 1):
				for xi in range(tx * TILE, (tx + 1) * TILE + 1):
					data.append(_h(xi, zi))
			var shape := HeightMapShape3D.new()
			shape.map_width = TILE + 1
			shape.map_depth = TILE + 1
			shape.map_data = data
			var shape_path := GEN + "terrain_shape_%d_%d.res" % [tx, tz]
			ResourceSaver.save(shape, shape_path)
			var body := StaticBody3D.new()
			body.name = "TerrainCollision_%d_%d" % [tx, tz]
			body.position = Vector3(tx * TILE + TILE * 0.5 - L.HALF, 0.0, tz * TILE + TILE * 0.5 - L.HALF)
			var collision := CollisionShape3D.new()
			collision.name = "HeightField"
			collision.shape = load(shape_path)
			body.add_child(collision)
			root_node.add_child(body)


## Earth-coloured walls from the terrain edge down to below the neighbouring ground, on the
## sides of tile (tx, tz) that are the vale's outer edge.
func _skirts(st: SurfaceTool, tx: int, tz: int, tiles: int) -> void:
	var bottom := -6.0
	var earth := Color(0.38, 0.31, 0.24)
	var sides: Array = []
	if tz == 0:
		sides.append([Vector2i(1, 0), 0, Vector2(0, -1)])
	if tz == tiles - 1:
		sides.append([Vector2i(1, 0), L.GRID - 1, Vector2(0, 1)])
	if tx == 0:
		sides.append([Vector2i(0, 1), 0, Vector2(-1, 0)])
	if tx == tiles - 1:
		sides.append([Vector2i(0, 1), L.GRID - 1, Vector2(1, 0)])
	for side: Array in sides:
		var along: Vector2i = side[0]
		var fixed: int = side[1]
		var out: Vector2 = side[2]
		var start := tx * TILE if along.x == 1 else tz * TILE
		for i in range(start, start + TILE):
			var a := Vector2i(i, fixed) if along.x == 1 else Vector2i(fixed, i)
			var b := a + along
			var top_a := Vector3(a.x - L.HALF, _h(a.x, a.y), a.y - L.HALF)
			var top_b := Vector3(b.x - L.HALF, _h(b.x, b.y), b.y - L.HALF)
			var low_a := Vector3(top_a.x, bottom, top_a.z)
			var low_b := Vector3(top_b.x, bottom, top_b.z)
			var normal := Vector3(out.x, 0.0, out.y)
			st.set_normal(normal)
			st.set_color(earth)
			# Wind the quad so its front faces outward.
			var quad := [top_a, top_b, low_b, top_a, low_b, low_a]
			if (top_b - top_a).cross(low_a - top_a).dot(normal) < 0.0:
				quad = [top_a, low_b, top_b, top_a, low_a, low_b]
			for v: Vector3 in quad:
				st.add_vertex(v)


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.y < 0.0:
		normal = -normal
		var t := b
		b = c
		c = t
	var centre := (a + b + c) / 3.0
	st.set_normal(normal)
	st.set_color(_ground_color(centre, normal))
	# (a, b, c) with (c - a) x (b - a) pointing up is a front face in Godot.
	for v in [a, b, c]:
		st.add_vertex(v)


func _ground_color(p: Vector3, normal: Vector3) -> Color:
	var flat := Vector2(p.x, p.z)
	var n := sin(p.x * 0.31 + p.z * 0.17) * 0.5 + sin(p.x * 0.07 - p.z * 0.11) * 0.5
	var jitter := rng.randf_range(-0.025, 0.025)
	var grass := Color(0.36, 0.56, 0.25).lerp(Color(0.5, 0.64, 0.3), n * 0.5 + 0.5)
	var color := grass
	if p.y > L.PLATEAU_HEIGHT - 2.5:
		color = Color(0.34, 0.5, 0.27).lerp(Color(0.44, 0.56, 0.3), n * 0.5 + 0.5)
	if maxf(absf(p.x), absf(p.z)) > L.BOUNDARY:
		color = color.lerp(Color(0.33, 0.45, 0.27), 0.5)
	# Open world: towards the south edge the grass darkens into the Whisperwood's floor, with
	# a wavy (noise) blend so the seam is no straight line.
	var forest := smoothstep(38.0, L.HALF, p.z + n * 6.0)
	color = color.lerp(Color(0.25, 0.36, 0.19).lerp(Color(0.33, 0.4, 0.22), n * 0.5 + 0.5), forest * 0.85)
	var road := L.road_distance(flat)
	if road < 0.0:
		color = Color(0.6, 0.48, 0.33).lerp(Color(0.66, 0.55, 0.38), n * 0.5 + 0.5)
	elif road < 0.6:
		color = color.lerp(Color(0.58, 0.5, 0.34), 0.5)
	if p.y < L.WATER_Y + 0.55 and p.y < L.PLATEAU_HEIGHT - 3.0:
		# Banks: wet sand to river stones under the water.
		color = Color(0.62, 0.57, 0.44) if p.y > L.WATER_Y - 0.1 else Color(0.42, 0.4, 0.33)
	if normal.y < 0.72:
		var band := sin(p.y * 2.3) * 0.5 + 0.5
		color = Color(0.46, 0.44, 0.42).lerp(Color(0.58, 0.55, 0.5), band)
		if normal.y > 0.6:
			color = color.lerp(grass, 0.35)
	return Color(color.r + jitter, color.g + jitter, color.b + jitter)


# --- water ---------------------------------------------------------------------

func _water_material(flow: Vector2, speed: float) -> ShaderMaterial:
	var material := (load(WATER_PRESET) as ShaderMaterial).duplicate() as ShaderMaterial
	material.set_shader_parameter(&"wind_direction", flow)
	material.set_shader_parameter(&"wind_speed", speed)
	# Greener and deeper than the village pond's preset: a mountain river.
	material.set_shader_parameter(&"shallow_color", Color(0.3, 0.62, 0.6))
	material.set_shader_parameter(&"deep_color", Color(0.06, 0.27, 0.38))
	material.set_shader_parameter(&"depth_distance", 1.6)
	return material


func _water() -> void:
	var group := Node3D.new()
	group.name = "Water"
	root_node.add_child(group)
	# Pool: a disc reaching under the banks.
	var pool := MeshInstance3D.new()
	pool.name = "FallsPool"
	pool.mesh = _disc(L.POOL_CENTRE, L.POOL_RADIUS + 2.2, L.WATER_Y)
	pool.material_override = _water_material(Vector2(0.4, 1.0), 0.9)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(pool)
	# River: a ribbon from the pool's rim downstream.
	var river_points: Array = []
	for p in _resample(L.RIVER, 1.0):
		if p.distance_to(L.POOL_CENTRE) > L.POOL_RADIUS - 1.0:
			river_points.append(p)
	var river := MeshInstance3D.new()
	river.name = "WyrmRiver"
	river.mesh = _ribbon(river_points, L.RIVER_HALF_WIDTH + 1.6, func(_p: Vector2) -> float: return L.WATER_Y)
	river.material_override = _water_material(Vector2(0.6, 0.7), 1.6)
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(river)
	var stream := MeshInstance3D.new()
	stream.name = "PlateauStream"
	stream.mesh = _ribbon(_resample(L.STREAM, 1.0), L.STREAM_HALF_WIDTH + 0.5, func(_p: Vector2) -> float: return _stream_water_y())
	stream.material_override = _water_material(Vector2(0.1, 1.0), 2.2)
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(stream)

	# Fishing water (no geometry): the river and the pool.
	var river_water := Node3D.new()
	river_water.set_script(RIVER_WATER)
	river_water.name = "FixedWyrmRiver"
	var points := PackedVector3Array()
	for p in L.RIVER:
		points.append(Vector3(p.x, 0.0, p.y))
	river_water.set(&"points", points)
	river_water.set(&"half_width", L.RIVER_HALF_WIDTH)
	river_water.set(&"water_height", L.WATER_Y)
	_set_fish(river_water, [45.0, 45.0, 10.0])
	group.add_child(river_water)
	var pool_water := Node3D.new()
	pool_water.set_script(RIVER_WATER)
	pool_water.name = "FixedFallsPool"
	# A disc: a "river" whose centreline is (almost) a point.
	pool_water.set(&"points", PackedVector3Array([Vector3(L.POOL_CENTRE.x, 0.0, L.POOL_CENTRE.y), Vector3(L.POOL_CENTRE.x + 0.01, 0.0, L.POOL_CENTRE.y)]))
	pool_water.set(&"half_width", L.POOL_RADIUS - 0.3)
	pool_water.set(&"water_height", L.WATER_Y)
	# Under the falls the rare carp bite more often.
	_set_fish(pool_water, [30.0, 45.0, 25.0])
	group.add_child(pool_water)

	var camp_bank := L.polyline_closest(L.CAMP_CENTRE, L.RIVER)
	var to_camp := (L.CAMP_CENTRE - camp_bank).normalized()
	_fishing_spot(group, "RiverBank", camp_bank + to_camp * (L.RIVER_HALF_WIDTH + 1.3), -to_camp, river_water, &"wyrmfall_river_bank", "the Wyrm River", 1.5)
	var pool_dir := Vector2(-0.75, 0.66).normalized()
	_fishing_spot(group, "PoolBank", L.POOL_CENTRE + pool_dir * (L.POOL_RADIUS + 0.9), -pool_dir, pool_water, &"wyrmfall_pool_bank", "the Falls Pool", 2.0)


func _stream_water_y() -> float:
	return L.PLATEAU_HEIGHT - 1.1 + L.STREAM_WATER_DROP


func _set_fish(water: Node, weights: Array) -> void:
	var fish: Array[MaterialItem] = []
	for path in FISH:
		fish.append(load(path) as MaterialItem)
	water.set(&"fish", fish)
	water.set(&"fish_weights", PackedFloat32Array(weights))


func _fishing_spot(parent: Node, node_name: String, at: Vector2, facing: Vector2, water: Node, id: StringName, label: String, bonus: float) -> void:
	var spot := Node3D.new()
	spot.set_script(FISHING_SPOT)
	spot.name = node_name
	spot.transform = Transform3D(Basis.looking_at(Vector3(facing.x, 0.0, facing.y)), _at(at))
	var cast := Marker3D.new()
	cast.name = "CastPoint"
	cast.position = Vector3(0, 0, -3.0)
	spot.add_child(cast)
	var area := _interactable("Interactable", 0.9)
	area.position = Vector3(0, 0.6, 0)
	spot.add_child(area)
	parent.add_child(spot)
	spot.set(&"pond", water)
	spot.set(&"cast_point", cast)
	spot.set(&"catch_bonus", bonus)
	spot.set(&"target_id", id)
	spot.set(&"display_name", label)
	obstacles.append([at, 1.5])


func _interactable(node_name: String, radius: float) -> Area3D:
	var area := Area3D.new()
	area.set_script(INTERACTABLE)
	area.name = node_name
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	shape.name = "Range"
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	area.add_child(shape)
	return area


## Points along a polyline about `step` apart (corners kept).
func _resample(points: Array, step: float) -> Array:
	var out: Array = [points[0]]
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var count := maxi(1, ceili(a.distance_to(b) / step))
		for k in range(1, count + 1):
			out.append(a.lerp(b, float(k) / count))
	return out


func _ribbon(points: Array, half_width: float, y_of: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in points.size():
		var p: Vector2 = points[i]
		var prev: Vector2 = points[maxi(i - 1, 0)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var dir := (next - prev).normalized()
		var side := Vector2(-dir.y, dir.x) * half_width
		var y: float = y_of.call(p)
		lefts.append(Vector3(p.x + side.x, y, p.y + side.y))
		rights.append(Vector3(p.x - side.x, y, p.y - side.y))
	st.set_normal(Vector3.UP)
	for i in points.size() - 1:
		_quad_up(st, lefts[i], rights[i], rights[i + 1], lefts[i + 1])
	return st.commit()


## Adds two upward-facing triangles for the quad a b c d (any winding).
func _quad_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for tri in [[a, b, c], [a, c, d]]:
		var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0])
		if n.y >= 0.0:
			st.add_vertex(tri[0]); st.add_vertex(tri[1]); st.add_vertex(tri[2])
		else:
			st.add_vertex(tri[0]); st.add_vertex(tri[2]); st.add_vertex(tri[1])


func _disc(centre: Vector2, radius: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var c := Vector3(centre.x, y, centre.y)
	var segments := 40
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * radius
		_quad_up(st, c, p0, p1, p1)
	return st.commit()


# --- waterfall -----------------------------------------------------------------

## z where the terrain at x falls to height y (the cliff face), searched downhill.
func _cliff_z(x: float, y: float) -> float:
	var lo := L.CLIFF_TOP_Z - 3.0
	var hi := L.CLIFF_BASE_Z + 3.0
	for i in 30:
		var mid := (lo + hi) * 0.5
		if surface_y(x, mid) > y:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _waterfall() -> void:
	var group := Node3D.new()
	group.name = "Waterfall"
	root_node.add_child(group)
	var top := _stream_water_y()
	var rows := 24
	var columns := 8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in rows + 1:
		var v := float(r) / rows
		# Rows bunch up near the lip, where the sheet curves over.
		var y := lerpf(top, L.WATER_Y - 0.05, pow(v, 1.15))
		var row: Array = []
		for c in columns + 1:
			var u := float(c) / columns
			var x := L.FALLS_X + (u - 0.5) * L.FALLS_WIDTH
			var z := _cliff_z(x, y) + lerpf(0.35, 0.9, smoothstep(0.0, 0.25, v))
			row.append([Vector3(x, y, z), Vector2(u, v)])
		grid.append(row)
	for r in rows:
		for c in columns:
			var a: Array = grid[r][c]
			var b: Array = grid[r][c + 1]
			var cc: Array = grid[r + 1][c + 1]
			var d: Array = grid[r + 1][c]
			for tri in [[a, cc, b], [a, d, cc]]:
				for vert: Array in tri:
					st.set_uv(vert[1])
					st.set_normal(Vector3(0, 0.2, 1).normalized())
					st.add_vertex(vert[0])
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = load(WATERFALL_SHADER)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.05
	var streaks := NoiseTexture2D.new()
	streaks.width = 64
	streaks.height = 256
	streaks.seamless = true
	streaks.noise = noise
	material.set_shader_parameter(&"streak_texture", streaks)
	sheet.material_override = material
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(sheet)

	var base_z := _cliff_z(L.FALLS_X, L.WATER_Y) + 1.0
	var plunge := Vector3(L.FALLS_X, L.WATER_Y, base_z)
	group.add_child(_mist("Mist", plunge + Vector3(0, 0.4, 0.6), Vector3(L.FALLS_WIDTH * 0.6, 0.3, 0.8), 36, 2.8, 0.55, 1.4, Color(1, 1, 1, 0.32)))
	group.add_child(_mist("Spray", plunge + Vector3(0, 0.15, 0.3), Vector3(L.FALLS_WIDTH * 0.5, 0.1, 0.4), 40, 0.9, 0.12, 2.6, Color(1, 1, 1, 0.8)))
	var foam := MeshInstance3D.new()
	foam.name = "PlungeFoam"
	foam.mesh = _disc(Vector2(plunge.x, plunge.z + 0.6), 2.6, L.WATER_Y + 0.03)
	var foam_material := StandardMaterial3D.new()
	foam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam_material.albedo_texture = _soft_dot()
	foam_material.albedo_color = Color(1, 1, 1, 0.55)
	foam_material.uv1_triplanar = true
	foam_material.uv1_world_triplanar = true
	foam_material.uv1_scale = Vector3(0.19, 0.19, 0.19)
	foam_material.uv1_offset = Vector3(0.5 - plunge.x * 0.19, 0.0, 0.5 - (plunge.z + 0.6) * 0.19)
	foam.material_override = foam_material
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(foam)


func _soft_dot() -> GradientTexture2D:
	if not _cache.has("dot"):
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		_cache["dot"] = texture
	return _cache["dot"]


func _mist(node_name: String, at: Vector3, extents: Vector3, amount: int, size: float, speed: float, lifetime: float, color: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = at
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.visibility_aabb = AABB(Vector3(-5, -1, -4), Vector3(10, 7, 8))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3(0, 1, 0.6)
	process.spread = 35.0
	process.initial_velocity_min = speed * 0.6
	process.initial_velocity_max = speed * 1.4
	process.gravity = Vector3(0, -0.4 if size > 1.0 else -6.0, 0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.4))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = curve
	process.scale_curve = scale_curve
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.6, Color(1, 1, 1, 0.8))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	material.albedo_texture = _soft_dot()
	quad.material = material
	particles.draw_pass_1 = quad
	return particles


# --- walls ---------------------------------------------------------------------

func _walls() -> void:
	var faces := PackedVector3Array()
	var low := -4.0
	var high := 30.0
	var b := L.BOUNDARY
	var corners := [Vector2(-b, -b), Vector2(b, -b), Vector2(b, b), Vector2(-b, b), Vector2(-b, -b)]
	for i in 4:
		if i == 2:
			# South edge: open where the pass comes in from the Whisperwood, with walls
			# along the pass to the vale's edge.
			var pass_x: float = (L.PASS[0] as Vector2).x
			_wall(faces, corners[2], Vector2(pass_x + L.PASS_OPEN, b), low, high)
			_wall(faces, Vector2(pass_x - L.PASS_OPEN, b), corners[3], low, high)
			for x in [pass_x - L.PASS_OPEN, pass_x + L.PASS_OPEN]:
				_wall(faces, Vector2(x, b), Vector2(x, L.HALF), low, high)
			continue
		_wall(faces, corners[i], corners[i + 1], low, high)
	# Foot of the cliff (the plateau is scenery).
	_wall(faces, Vector2(-b, L.CLIFF_BASE_Z + 0.7), Vector2(b, L.CLIFF_BASE_Z + 0.7), low, high)
	var bridge := L.bridge_point()
	var along := L.bridge_direction()
	var edge := L.RIVER_HALF_WIDTH + 1.0
	var pool_edge := L.POOL_RADIUS + 0.7
	# River banks, both sides, in short pieces: open where the bridge crosses, not inside
	# the pool, not behind the cliff wall.
	for i in L.RIVER.size() - 1:
		var a: Vector2 = L.RIVER[i]
		var c: Vector2 = L.RIVER[i + 1]
		var dir := (c - a).normalized()
		var normal := Vector2(-dir.y, dir.x)
		for side in [-1.0, 1.0]:
			var from: Vector2 = a - dir * 0.6 + normal * edge * side
			var to: Vector2 = c + dir * 0.6 + normal * edge * side
			var pieces := maxi(1, ceili(from.distance_to(to) / 0.5))
			for k in pieces:
				var p0 := from.lerp(to, float(k) / pieces)
				var p1 := from.lerp(to, float(k + 1) / pieces)
				var mid := (p0 + p1) * 0.5
				if L.river_distance(mid) < edge - 0.3:
					continue  # inside a bend: the other segment's wall covers it
				if mid.distance_to(L.POOL_CENTRE) < pool_edge or mid.y < L.CLIFF_BASE_Z + 0.7:
					continue
				var rel := mid - bridge
				if absf(rel.dot(along)) < 6.0 and absf(rel.cross(along)) < 1.75:
					continue
				_wall(faces, p0, p1, low, 3.0)
	# Pool rim, open where the river leaves.
	var segments := 48
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := L.POOL_CENTRE + Vector2(cos(a0), sin(a0)) * pool_edge
		var p1 := L.POOL_CENTRE + Vector2(cos(a1), sin(a1)) * pool_edge
		var mid := (p0 + p1) * 0.5
		if L.river_distance(mid) < edge or mid.y < L.CLIFF_BASE_Z + 0.7:
			continue
		_wall(faces, p0, p1, low, 3.0)
	var body := StaticBody3D.new()
	body.name = "Walls"
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	root_node.add_child(body)


func _wall(faces: PackedVector3Array, a: Vector2, b: Vector2, low: float, high: float) -> void:
	var a0 := Vector3(a.x, low, a.y)
	var b0 := Vector3(b.x, low, b.y)
	var a1 := Vector3(a.x, high, a.y)
	var b1 := Vector3(b.x, high, b.y)
	faces.append_array([a0, b0, b1, a0, b1, a1])


# --- bridge, camp, ruins -------------------------------------------------------

func _bridge() -> void:
	var at := L.bridge_point()
	var dir := L.bridge_direction()
	var mesh := _newmap_mesh("Bridge01")
	var length := mesh.get_aabb().size.z
	var y := maxf(surface_y(at.x + dir.x * length * 0.5, at.y + dir.y * length * 0.5), surface_y(at.x - dir.x * length * 0.5, at.y - dir.y * length * 0.5)) - 0.08
	var body := StaticBody3D.new()
	body.name = "OldStoneBridge"
	body.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(at.x, y, at.y))
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = mesh
	body.add_child(model)
	# The model's ends are steps: walk on a smooth deck traced from the mesh instead, ramped
	# down to the ground past each end, with railings along both sides.
	var faces := mesh.get_faces()
	var aabb := mesh.get_aabb()
	var half_deck := 1.3
	var samples := 24
	var profile: Array[Vector3] = []
	var ground_a := surface_y(at.x - dir.x * (length * 0.5 + 1.2), at.y - dir.y * (length * 0.5 + 1.2)) - y
	var ground_b := surface_y(at.x + dir.x * (length * 0.5 + 1.2), at.y + dir.y * (length * 0.5 + 1.2)) - y
	profile.append(Vector3(0, ground_a - 0.15, aabb.position.z - 1.2))
	for i in samples + 1:
		var z := lerpf(aabb.position.z + 0.15, aabb.end.z - 0.15, float(i) / samples)
		profile.append(Vector3(0, _deck_height(faces, z, aabb), z))
	profile.append(Vector3(0, ground_b - 0.15, aabb.end.z + 1.2))
	# Smooth the steps out of the traced profile.
	for pass_index in 3:
		for i in range(1, profile.size() - 1):
			var point := profile[i]
			if pass_index == 0:
				point.y = maxf(point.y, (profile[i - 1].y + profile[i + 1].y) * 0.5)
			else:
				point.y = (profile[i - 1].y + point.y * 2.0 + profile[i + 1].y) * 0.25
			profile[i] = point
	var deck := PackedVector3Array()
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		var l0 := Vector3(-half_deck, p0.y, p0.z)
		var r0 := Vector3(half_deck, p0.y, p0.z)
		var l1 := Vector3(-half_deck, p1.y, p1.z)
		var r1 := Vector3(half_deck, p1.y, p1.z)
		deck.append_array([l0, r0, r1, l0, r1, l1])
		if i > 0 and i < profile.size() - 2:
			for x in [-half_deck - 0.05, half_deck + 0.05]:
				var a0 := Vector3(x, p0.y - 0.5, p0.z)
				var b0 := Vector3(x, p1.y - 0.5, p1.z)
				deck.append_array([a0, b0, b0 + Vector3.UP * 1.6, a0, b0 + Vector3.UP * 1.6, a0 + Vector3.UP * 1.6])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(deck)
	ResourceSaver.save(shape, GEN + "bridge_collision.res")
	var collision := CollisionShape3D.new()
	collision.name = "Deck"
	collision.shape = load(GEN + "bridge_collision.res")
	body.add_child(collision)
	root_node.add_child(body)
	obstacles.append([at, 6.0])


## Highest point of the mesh above (0, z) in model space (the walking surface).
func _deck_height(faces: PackedVector3Array, z: float, aabb: AABB) -> float:
	var best := 0.0
	var from := Vector3(0, aabb.end.y + 1.0, z)
	for i in range(0, faces.size(), 3):
		for x in [-0.6, 0.0, 0.6]:
			var hit: Variant = Geometry3D.ray_intersects_triangle(from + Vector3(x, 0, 0), Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
			if hit != null and (hit as Vector3).y > best and (hit as Vector3).y < 2.4:
				best = (hit as Vector3).y
	return best


func _camp() -> void:
	var camp := Node3D.new()
	camp.name = "FishersCamp"
	root_node.add_child(camp)
	var c := L.CAMP_CENTRE
	_newmap_prop(camp, "Hut", "Stylized_Hut01", c + Vector2(-4.0, 4.5), deg_to_rad(15.0), 1.0, 0.8)
	_newmap_prop(camp, "Stall", "Market03", c + Vector2(5.0, 1.5), deg_to_rad(-60.0), 0.9, 0.8)
	_newmap_prop(camp, "Barrel1", "Barrel01", c + Vector2(1.5, 5.0), deg_to_rad(30.0), 1.0, 0.8)
	_newmap_prop(camp, "Barrel2", "Barrel03", c + Vector2(2.6, 5.6), 0.0, 1.0, 0.8)
	_newmap_prop(camp, "Crate", "Box01", c + Vector2(3.4, 4.7), deg_to_rad(20.0), 1.0, 0.8)
	_newmap_prop(camp, "Bench", "Bench01", c + Vector2(-0.5, -1.8), deg_to_rad(10.0), 1.0, 0.0)
	_newmap_prop(camp, "Firepit", "Brazier", c + Vector2(0.2, 0.6), 0.0, 1.2, 0.0)
	_newmap_prop(camp, "Ladder", "Ladder", c + Vector2(-1.0, 4.4), deg_to_rad(15.0), 1.0, 0.0)
	_newmap_prop(camp, "Wheel", "Wheel_L", c + Vector2(6.0, 4.2), deg_to_rad(80.0), 1.0, 0.0, 0.0)
	_newmap_prop(camp, "Vase1", "ClayVase01", c + Vector2(4.2, -1.2), 0.0, 1.0, 0.0)
	_newmap_prop(camp, "Vase2", "ClayVase03", c + Vector2(4.8, -0.8), 0.0, 1.0, 0.0)
	for i in 3:
		_newmap_prop(camp, "Fence%d" % i, "FenceWood_H01", c + Vector2(-8.5 + i * 2.1, 8.5), deg_to_rad(4.0), 1.0, 0.9)
	var fire := OmniLight3D.new()
	fire.name = "FireLight"
	fire.position = _at(c + Vector2(0.2, 0.6), 1.0)
	fire.light_color = Color(1.0, 0.62, 0.3)
	fire.light_energy = 1.6
	fire.omni_range = 6.0
	camp.add_child(fire)
	obstacles.append([c, 7.5])
	# Lamps along the road, on the side away from the camera.
	var lamps := Node3D.new()
	lamps.name = "RoadLamps"
	root_node.add_child(lamps)
	var index := 0
	var travelled := 0.0
	var next_lamp := 6.0
	for i in L.ROAD.size() - 1:
		var a: Vector2 = L.ROAD[i]
		var b: Vector2 = L.ROAD[i + 1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		if side.dot(CAMERA_DIR) > 0.0:
			side = -side
		while next_lamp < travelled + a.distance_to(b):
			var p := a + dir * (next_lamp - travelled) + side * (L.ROAD_HALF_WIDTH + 0.9)
			next_lamp += 16.0
			if L.river_distance(p) < L.RIVER_BANK + 1.0:
				continue
			var lamp := _newmap_prop(lamps, "Lamp%d" % index, "Streetlamp01", p, atan2(-side.x, -side.y), 1.0, 0.0)
			var pole := CollisionShape3D.new()
			pole.name = "Pole"
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.25
			cylinder.height = 3.0
			pole.shape = cylinder
			pole.position = Vector3(0, 1.5, 0)
			var body := StaticBody3D.new()
			body.name = "Body"
			body.add_child(pole)
			lamp.add_child(body)
			var light := OmniLight3D.new()
			light.name = "Glow"
			light.position = Vector3(0, 3.6, 0)
			light.light_color = Color(1.0, 0.8, 0.5)
			light.light_energy = 0.6
			light.omni_range = 5.0
			lamp.add_child(light)
			obstacles.append([p, 1.2])
			index += 1
		travelled += a.distance_to(b)


func _ruins() -> void:
	var ruins := Node3D.new()
	ruins.name = "DrakewardRuins"
	root_node.add_child(ruins)
	var c := L.RUINS_CENTRE
	var walls := ["Wall_Stone01", "Wall_Stone02", "Wall_Stone03", "Wall_Stone04", "Wall_Stone05", "Wall_Stone01", "Wall_Stone03"]
	# A broken ring of walls, open towards the path (south-east).
	var angles := [200.0, 245.0, 290.0, 335.0, 20.0, 110.0, 155.0]
	for i in walls.size():
		var a := deg_to_rad(angles[i])
		var p := c + Vector2(cos(a), sin(a)) * 5.5
		_newmap_prop(ruins, "Wall%d" % i, walls[i], p, -a + PI * 0.5, 1.0, 0.95, 0.15)
	_newmap_prop(ruins, "DeadGiant", "Trunk04", c + Vector2(-1.0, -1.5), deg_to_rad(40.0), 0.8, 0.0)
	var trunk := StaticBody3D.new()
	trunk.name = "DeadGiantTrunk"
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.0
	cylinder.height = 4.0
	shape.shape = cylinder
	trunk.add_child(shape)
	trunk.position = _at(c + Vector2(-1.0, -1.5), 2.0)
	ruins.add_child(trunk)
	_newmap_prop(ruins, "Rubble1", "RockMedium", c + Vector2(2.5, 1.0), 0.7, 1.0, 0.0)
	_newmap_prop(ruins, "Rubble2", "RockSmall", c + Vector2(1.5, 2.6), 1.9, 1.3, 0.0)
	_newmap_prop(ruins, "Stump", "Trunk02", c + Vector2(-8.5, 3.0), 2.4, 1.0, 0.8)
	obstacles.append([c, 7.5])


## The pass from the Whisperwood: a signpost pointing home, and the Arrival marker (where
## a test or fast travel puts the courier in the vale).
func _pass() -> void:
	var sign_post := (load(SIGNPOST) as PackedScene).instantiate() as Node3D
	sign_post.name = "WillowmereSign"
	sign_post.set(&"text", "Willowmere")
	sign_post.transform = Transform3D(Basis(Vector3.UP, PI), _at(Vector2(-36.0, 50.5)))
	root_node.add_child(sign_post)
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	root_node.add_child(spawns)
	var arrival := Marker3D.new()
	arrival.name = "Arrival"
	arrival.position = _at(L.ARRIVAL, 0.1)
	spawns.add_child(arrival)
	for point: Vector2 in L.PASS:
		obstacles.append([point, 6.5])
	obstacles.append([L.ARRIVAL, 4.0])


# --- tool sites, places, creatures ---------------------------------------------

func _tool_sites() -> void:
	var sites := Node3D.new()
	sites.name = "ToolSites"
	root_node.add_child(sites)
	var entries := [
		[TOOL_TREE, "WyrmfallTree1", &"wyrmfall_tree_1", Vector2(30.0, 5.0)],
		[TOOL_TREE, "WyrmfallTree2", &"wyrmfall_tree_2", Vector2(37.0, -3.0)],
		[TOOL_ROCK, "WyrmfallRock1", &"wyrmfall_rock_1", Vector2(11.0, -17.6)],
		[TOOL_ROCK, "WyrmfallRock2", &"wyrmfall_rock_2", Vector2(42.0, -17.4)],
		[TOOL_SOIL, "WyrmfallSoil1", &"wyrmfall_soil_1", L.CAMP_CENTRE + Vector2(-8.0, 1.0)],
	]
	for entry in entries:
		var node := (load(entry[0]) as PackedScene).instantiate() as Node3D
		node.name = entry[1]
		node.set(&"target_id", entry[2])
		node.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), _at(entry[3]))
		sites.add_child(node)
		obstacles.append([entry[3], 2.6])


func _locations() -> void:
	var places := Node3D.new()
	places.name = "Locations"
	root_node.add_child(places)
	var bridge := L.bridge_point()
	# id, name, subtitle, kind, position, discover radius, hidden
	var entries := [
		[&"wyrmfall_pass", "Wyrmfall Pass", "The trail from the Whisperwood", WorldLocation.Kind.CLEARING, Vector2(-40.0, 50.0), 9.0, false],
		[&"wyrmfall_falls", "Wyrmfall", "The great falls and their pool", WorldLocation.Kind.CLEARING, L.POOL_CENTRE + Vector2(0, 3), 12.0, true],
		[&"wyrmfall_bridge", "Old Stone Bridge", "Over the Wyrm River", WorldLocation.Kind.CLEARING, bridge, 8.0, true],
		[&"wyrmfall_ruins", "Drakeward Ruins", "Walls older than Willowmere", WorldLocation.Kind.CLEARING, L.RUINS_CENTRE, 9.0, true],
		[&"wyrmfall_camp", "Fisher's Camp", "A good spot on the river", WorldLocation.Kind.TOWN, L.CAMP_CENTRE, 9.0, true],
		[&"wyrmfall_cliffs", "Ember Cliffs", "Where the road meets the rock", WorldLocation.Kind.FOREST, L.CLIFF_END, 9.0, true],
	]
	for entry in entries:
		var marker := Marker3D.new()
		marker.set_script(LOCATION)
		marker.name = String(entry[0])
		marker.position = _at(entry[4])
		marker.set(&"location_id", entry[0])
		marker.set(&"display_name", entry[1])
		marker.set(&"subtitle", entry[2])
		marker.set(&"kind", entry[3])
		marker.set(&"discover_radius", entry[5])
		marker.set(&"hidden_until_discovered", entry[6])
		# Open world: the vale is part of the overworld (one map, one fog of war).
		marker.set(&"region_id", &"village")
		places.add_child(marker)


func _creatures() -> void:
	var creatures := Node3D.new()
	creatures.name = "Creatures"
	root_node.add_child(creatures)
	# Over 9 m from the tool sites, so working a site doesn't wake them (detection 8 m).
	for p in [Vector2(46.0, 16.0), Vector2(20.0, -9.0), Vector2(47.0, 30.0)]:
		var slime := (load(SLIME) as PackedScene).instantiate() as Node3D
		slime.name = "Slime%d" % creatures.get_child_count()
		slime.position = _at(p, 0.3)
		creatures.add_child(slime)
		obstacles.append([p, 2.0])


# --- vegetation ----------------------------------------------------------------

func _free_at(p: Vector2, radius: float) -> bool:
	for obstacle in obstacles:
		if p.distance_to(obstacle[0]) < radius + float(obstacle[1]):
			return false
	return true


## Distance to the nearest place the courier walks or looks at (negative inside it).
func _open_distance(p: Vector2) -> float:
	var d := L.road_distance(p)
	d = minf(d, L.river_distance(p) - L.RIVER_BANK)
	d = minf(d, p.distance_to(L.POOL_CENTRE) - L.POOL_RADIUS - 3.0)
	return d


func _cliff_rocks() -> void:
	var rocks := Node3D.new()
	rocks.name = "CliffRocks"
	root_node.add_child(rocks)
	var x := -L.BOUNDARY + 2.0
	var index := 0
	while x < L.BOUNDARY - 2.0:
		x += rng.randf_range(3.5, 6.0)
		if absf(x - L.FALLS_X) < 4.5:
			continue
		var p := Vector2(x, L.CLIFF_BASE_Z - 0.2 + rng.randf_range(-0.4, 0.4))
		if not _free_at(p, 1.0):
			continue
		var model := (_load(NATURE + ["Rock_5", "Rock_6", "Rock_Moss_4"][index % 3] + ".fbx") as PackedScene).instantiate() as Node3D
		model.name = "CliffRock%02d" % index
		var s := rng.randf_range(1.8, 2.8)
		model.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), _at(p, -0.3))
		rocks.add_child(model)
		obstacles.append([p, 1.5])
		index += 1


func _trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	root_node.add_child(trees)
	var total := 0
	for entry in TREES:
		total += int(entry[1])
	var forest := FastNoiseLite.new()
	forest.seed = L.SEED + 5
	forest.frequency = 0.045
	var count := 0
	var step := 2.6
	var z := -L.HALF + 1.0
	while z < L.HALF - 1.0:
		var x := -L.HALF + 1.0
		while x < L.HALF - 1.0:
			var p := Vector2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0))
			x += step
			var plateau := L.plateau_factor(p.x, p.y)
			if plateau > 0.01 and plateau < 0.99:
				continue  # the cliff face
			if p.y > L.CLIFF_TOP_Z - 2.0 and p.y < L.CLIFF_BASE_Z + 2.0:
				continue
			var edge := maxf(absf(p.x), absf(p.y))
			var open := _open_distance(p)
			var chance := 0.0
			if plateau >= 0.99:
				if L.polyline_distance(p, L.STREAM) < L.STREAM_HALF_WIDTH + 2.5:
					continue
				chance = 0.55 if forest.get_noise_2d(p.x, p.y) > -0.2 else 0.15
				# Keep the falls' lip in view.
				if p.distance_to(Vector2(L.FALLS_X, L.CLIFF_TOP_Z)) < 9.0:
					continue
			elif edge > L.BOUNDARY - 1.0:
				chance = 0.85
			else:
				if open < 1.8:
					continue
				if _open_distance(p - CAMERA_DIR * 3.5) < 0.5:
					continue
				var dense := forest.get_noise_2d(p.x, p.y)
				chance = 0.75 if dense > 0.15 else (0.25 if dense > -0.15 else 0.05)
				# The falls stay in view from the vale.
				if absf(p.x - L.FALLS_X) < 14.0 and p.y < 2.0:
					chance *= 0.2
			if rng.randf() > chance or not _free_at(p, 1.5):
				continue
			var name: String
			var scale: float
			var trunk: float
			if plateau >= 0.99:
				name = PLATEAU_TREES[rng.randi() % PLATEAU_TREES.size()]
				scale = rng.randf_range(1.3, 1.8)
				trunk = 0.35
			elif L.river_distance(p) < L.RIVER_BANK + 4.0 and rng.randf() < 0.6:
				var willow: Array = WATERSIDE_TREES[rng.randi() % WATERSIDE_TREES.size()]
				name = willow[0]
				scale = rng.randf_range(willow[1], willow[2])
				trunk = willow[3]
			else:
				var pick := rng.randi_range(1, total)
				var entry: Array = TREES[0]
				for candidate in TREES:
					pick -= int(candidate[1])
					if pick <= 0:
						entry = candidate
						break
				name = entry[0]
				scale = rng.randf_range(float(entry[2]), float(entry[3]))
				trunk = entry[4]
			var collide := plateau < 0.99 and edge < L.BOUNDARY + 0.5
			trees.add_child(_tree(name, _at(p, -0.1), scale, trunk, count, collide))
			obstacles.append([p, 1.3])
			tree_points.append(p)
			count += 1
		z += step


func _tree(model_name: String, at: Vector3, scale: float, trunk: float, index: int, collide: bool) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collide else Node3D.new()
	body.name = "Tree%03d_%s" % [index, model_name]
	body.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale), at)
	var model := (_load(NATURE + model_name + ".fbx") as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	if collide:
		var shape := CollisionShape3D.new()
		shape.name = "Trunk"
		shape.shape = _trunk_shape(trunk)
		shape.position.y = 0.8
		body.add_child(shape)
		var occluder := OCCLUDER.new() as Node3D
		occluder.name = "CameraOccluder"
		occluder.set(&"radius", 1.9)
		occluder.set(&"height", 4.5)
		body.add_child(occluder)
	return body


func _trunk_shape(radius: float) -> CylinderShape3D:
	var key := "trunk%.2f" % radius
	if not _cache.has(key):
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = 1.6
		_cache[key] = shape
	return _cache[key]


func _props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	root_node.add_child(props)
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 3000:
		tries += 1
		var p := Vector2(rng.randf_range(-L.BOUNDARY + 2.0, L.BOUNDARY - 2.0), rng.randf_range(L.CLIFF_BASE_Z + 2.0, L.BOUNDARY - 2.0))
		if _open_distance(p) < 1.5 or not _free_at(p, 1.2):
			continue
		var node := (_load(ROCKS[rng.randi() % ROCKS.size()]) as PackedScene).instantiate() as Node3D
		node.name = "Rock%02d" % placed
		node.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), _at(p, -0.05))
		props.add_child(node)
		obstacles.append([p, 1.2])
		placed += 1
	# Foliage clumps from the newmap pack by the water.
	var clumps := 0
	tries = 0
	while clumps < 18 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(-L.BOUNDARY + 2.0, L.BOUNDARY - 2.0), rng.randf_range(L.CLIFF_BASE_Z + 1.5, L.BOUNDARY - 2.0))
		var river := L.river_distance(p)
		if river < L.RIVER_BANK + 0.3 or river > L.RIVER_BANK + 5.0 or L.road_distance(p) < 1.0 or not _free_at(p, 0.8):
			continue
		_newmap_prop(props, "Reeds%02d" % clumps, "Foliage01", p, rng.randf() * TAU, rng.randf_range(0.8, 1.2), 0.0)
		obstacles.append([p, 0.8])
		clumps += 1


func _undergrowth() -> void:
	var group := Node3D.new()
	group.name = "Undergrowth"
	root_node.add_child(group)
	# model, count, min open distance, scale range
	var layers := [
		["Bush_1", 70, 1.2, Vector2(0.9, 1.4)], ["Bush_2", 60, 1.2, Vector2(0.9, 1.4)],
		["BushBerries_1", 25, 1.0, Vector2(0.9, 1.2)], ["Plant_1", 70, 0.4, Vector2(0.9, 1.4)],
		["Plant_3", 60, 0.4, Vector2(0.9, 1.3)], ["Grass", 260, 0.2, Vector2(0.8, 1.3)],
		["Grass_2", 240, 0.2, Vector2(0.8, 1.3)], ["Grass_Short", 320, 0.0, Vector2(0.8, 1.2)],
		["Flowers", 160, 0.3, Vector2(0.8, 1.2)],
	]
	for layer in layers:
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < int(layer[1]) and tries < int(layer[1]) * 30:
			tries += 1
			var on_plateau := rng.randf() < 0.18
			var p := Vector2(rng.randf_range(-L.BOUNDARY, L.BOUNDARY), rng.randf_range(-L.BOUNDARY, L.CLIFF_TOP_Z - 2.0) if on_plateau else rng.randf_range(L.CLIFF_BASE_Z + 1.0, L.BOUNDARY))
			if _open_distance(p) < float(layer[2]):
				continue
			if on_plateau and L.polyline_distance(p, L.STREAM) < L.STREAM_HALF_WIDTH + 1.0:
				continue
			if String(layer[0]).begins_with("Bush") and not _free_at(p, 0.4):
				continue
			var scale_range: Vector2 = layer[3]
			var s := rng.randf_range(scale_range.x, scale_range.y)
			transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), _at(p, -0.03)))
		var field := MultiMeshInstance3D.new()
		field.set_script(SCATTER)
		field.name = String(layer[0]).to_pascal_case()
		field.set(&"source", _load(NATURE + String(layer[0]) + ".fbx"))
		field.set(&"transforms", transforms)
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if String(layer[0]).begins_with("Grass") or String(layer[0]).begins_with("Flowers") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		group.add_child(field)


# --- chunks --------------------------------------------------------------------

## Cuts the built vale into its streamed chunks and saves them with the chunk set.
func _split_and_save() -> void:
	var tiles := {}
	var count := (L.GRID - 1) / TILE
	for tz in count:
		for tx in count:
			tiles[Vector2i(tx, tz)] = _chunk_root("wyrmfall_%d_%d" % [tx, tz])
	var core := _chunk_root("wyrmfall_core")
	var places := _chunk_root("wyrmfall_places")
	for child in root_node.get_children():
		var child_name := String(child.name)
		if child_name in CORE_NODES:
			_move(child, core)
		elif child_name in PLACE_NODES:
			_move(child, places)
		elif child_name.begins_with("Terrain"):
			var parts := child_name.split("_")
			_move(child, tiles[Vector2i(int(parts[1]), int(parts[2]))])
		elif _is_group(child):
			# A plain group: each member goes to the tile it stands on, in a group of the
			# same name there. Scatter fields are split by instance.
			for member in child.get_children():
				if member is ScatterField:
					_split_scatter(member as ScatterField, child_name, tiles)
				else:
					_move(member, _group_in(tiles[_tile_of(member as Node3D)], child_name))
		else:
			_move(child, tiles[_tile_of(child as Node3D)])
	var chunk_set := WorldChunkSet.new()
	chunk_set.biome = &"wyrmfall"
	var whole := Rect2(L.WORLD_ORIGIN.x - L.HALF, L.WORLD_ORIGIN.z - L.HALF, L.HALF * 2.0, L.HALF * 2.0)
	for tile: Vector2i in tiles:
		var bounds := Rect2(L.WORLD_ORIGIN.x - L.HALF + tile.x * TILE, L.WORLD_ORIGIN.z - L.HALF + tile.y * TILE, TILE, TILE)
		chunk_set.chunks.append(_save_chunk(tiles[tile], bounds, false))
	chunk_set.chunks.append(_save_chunk(core, whole, false))
	chunk_set.chunks.append(_save_chunk(places, whole, true))
	var err := ResourceSaver.save(chunk_set, CHUNK_SET)
	print("saved %s (%d chunks) err=%d" % [CHUNK_SET, chunk_set.chunks.size(), err])


func _chunk_root(chunk_name: String) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = chunk_name
	chunk.position = L.WORLD_ORIGIN
	return chunk


func _save_chunk(chunk: Node3D, bounds: Rect2, always: bool) -> WorldChunk:
	var path := CHUNK_DIR + String(chunk.name) + ".tscn"
	_save(chunk, path)
	var entry := WorldChunk.new()
	entry.chunk_id = StringName(chunk.name)
	entry.scene_path = path
	entry.bounds = bounds
	entry.always_loaded = always
	entry.biome = &"wyrmfall"
	chunk.free()
	return entry


func _move(node: Node, target: Node) -> void:
	node.get_parent().remove_child(node)
	target.add_child(node)


func _is_group(node: Node) -> bool:
	return node.get_class() == "Node3D" and node.get_script() == null and node.get_child_count() > 0 \
			and (node as Node3D).transform.is_equal_approx(Transform3D.IDENTITY)


func _group_in(chunk: Node3D, group_name: String) -> Node3D:
	var group := chunk.get_node_or_null(NodePath(group_name)) as Node3D
	if group == null:
		group = Node3D.new()
		group.name = group_name
		chunk.add_child(group)
	return group


## The tile a node stands on (by its position in vale space).
func _tile_of(node: Node3D) -> Vector2i:
	return _tile_at(Vector2(node.position.x, node.position.z))


func _tile_at(p: Vector2) -> Vector2i:
	var last := (L.GRID - 1) / TILE - 1
	return Vector2i(clampi(floori((p.x + L.HALF) / TILE), 0, last), clampi(floori((p.y + L.HALF) / TILE), 0, last))


func _split_scatter(field: ScatterField, group_name: String, tiles: Dictionary) -> void:
	var parts := {}
	for xform: Transform3D in field.transforms:
		var tile := _tile_at(Vector2(xform.origin.x, xform.origin.z))
		if not parts.has(tile):
			parts[tile] = [] as Array[Transform3D]
		(parts[tile] as Array[Transform3D]).append(xform)
	for tile: Vector2i in parts:
		var piece := MultiMeshInstance3D.new()
		piece.set_script(SCATTER)
		piece.name = field.name
		piece.set(&"source", field.source)
		piece.set(&"colors", field.colors)
		piece.set(&"transforms", parts[tile])
		piece.cast_shadow = field.cast_shadow
		_group_in(tiles[tile], group_name).add_child(piece)


# --- map -------------------------------------------------------------------------

## The vale's part of the world map: vale space -HALF..HALF at 4 px/m. tools/bake_world_map.gd
## paints it into the one world map at WORLD_ORIGIN.
func _map_image() -> void:
	var rect := Rect2(-L.HALF, -L.HALF, L.HALF * 2.0, L.HALF * 2.0)
	var scale := 4.0
	var image := Image.create(int(rect.size.x * scale), int(rect.size.y * scale), false, Image.FORMAT_RGB8)
	var parchment := Color(0.2, 0.22, 0.2)
	for py in image.get_height():
		for px in image.get_width():
			var x := rect.position.x + (px + 0.5) / scale
			var z := rect.position.y + (py + 0.5) / scale
			if absf(x) > L.HALF - 0.5 or absf(z) > L.HALF - 0.5:
				image.set_pixel(px, py, parchment)
				continue
			var p := Vector2(x, z)
			var h := surface_y(x, z)
			var dx := surface_y(x + 1.0, z) - h
			var dz := surface_y(x, z + 1.0) - h
			var shade := clampf(1.0 - (dx + dz) * 0.35, 0.6, 1.25)
			var color := Color(0.45, 0.62, 0.33)
			if h > L.PLATEAU_HEIGHT - 2.5:
				color = Color(0.4, 0.56, 0.32)
			if Vector2(dx, dz).length() > 1.2:
				color = Color(0.55, 0.52, 0.48)
			if L.road_distance(p) < 0.0:
				color = Color(0.78, 0.66, 0.45)
			if L.is_water(p):
				color = Color(0.3, 0.56, 0.75)
			elif maxf(absf(x), absf(z)) > L.BOUNDARY:
				color = color.darkened(0.35)
			image.set_pixel(px, py, (color * shade).clamp())
	for p in tree_points:
		var px := int((p.x - rect.position.x) * scale)
		var py := int((p.y - rect.position.y) * scale)
		image.fill_rect(Rect2i(px - 2, py - 2, 5, 5), Color(0.22, 0.4, 0.22))
	image.save_png(ProjectSettings.globalize_path(GEN + "wyrmfall_map.png"))
	print("map saved")


func _load(path: String) -> Resource:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]
