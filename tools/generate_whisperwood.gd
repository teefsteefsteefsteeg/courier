extends SceneTree
## Phase 7: builds res://scenes/environment/whisperwood_forest.tscn, the dense Whisperwood
## around the relocated ForestEntrance (village.tscn places both; this scene sits at the
## world origin, so every position here is a world position). It fills the annex north of
## the village (x -18..42, z -122..-53) and thins out over the outskirts down to z -44:
##   Trees        varied Quaternius trees (pine, common, birch, autumn, willow, dead), each a
##                StaticBody3D with a trunk collider and a CameraOccluder so it fades when it
##                hides the courier; denser away from the trail, glades and clearing
##   Undergrowth  bushes, berry bushes, ferns, grass and flowers as ScatterField multimeshes
##   Props        moss rocks, mossy logs and mushroom clusters (a few of them glowing)
##   EdgeGate     a timber gate and signpost where the trail enters the wood
##   Atmosphere   a FogVolume over the wood (the village WorldEnvironment has volumetric fog
##                at zero density, so only the wood is misty) and fireflies over the glades
## Paths and clearings match tools/edit_village_splat.py (phase7_world). Placement keeps
## clear of everything that already has a collider (it loads village.tscn first), and of the
## portal, Elowen, the encounter spawns and the trail. Change this generator, not the scene:
##   godot --headless --path . --script res://tools/generate_whisperwood.gd

const OUT := "res://scenes/environment/whisperwood_forest.tscn"
const NATURE := "res://assets/models/quaternius/ultimate_nature/"
const OCCLUDER := preload("res://scripts/world/camera_occluder.gd")
const SCATTER := preload("res://scripts/world/scatter_field.gd")
const SIGNPOST := "res://scenes/props/signpost.tscn"
const GATE := "res://scenes/generated/wayfarer_open_gate.tscn"
const ROCKS := ["res://scenes/props/nature/rock_moss_2.tscn", "res://scenes/props/nature/rock_2.tscn", "res://scenes/props/nature/rock_3.tscn"]
const LOG := "res://scenes/props/env/log_moss.tscn"
const MUSHROOMS := "res://scenes/props/mushroom_cluster.tscn"
const MUSHROOMS_GLOW := "res://scenes/props/env/mushroom_glow.tscn"

const SEED := 7707
## The wood proper, and the outskirts it thins out over.
const WOOD := Rect2(-18.0, -122.0, 60.0, 69.0)
const OUTSKIRTS := Rect2(-18.0, -53.0, 60.0, 9.0)
const TRAIL := [Vector2(14.0, -28.6), Vector2(12.6, -36.0), Vector2(15.5, -45.0), Vector2(14.2, -53.0), Vector2(18.5, -62.0),
		Vector2(13.5, -71.0), Vector2(16.5, -80.0), Vector2(14.0, -90.0), Vector2(14.0, -98.6)]
## Phase 8 open world: the trail goes on north through the Moonstone Clearing to the Wyrmfall
## Pass at the wood's north edge (WyrmfallLayout.PASS starts at world (14, -124)).
const PASS_TRAIL := [Vector2(14.0, -104.0), Vector2(14.0, -111.0), Vector2(13.2, -117.5), Vector2(14.0, -124.0), Vector2(14.0, -126.0)]
const GLADE_PATH := [Vector2(13.5, -71.0), Vector2(6.0, -76.0), Vector2(-2.0, -80.0)]
const HOLLOW_PATH := [Vector2(16.5, -80.0), Vector2(25.0, -84.0), Vector2(31.0, -86.0), Vector2(35.0, -90.0)]
## (centre, radius) of open ground: the Moonstone Clearing and two glades.
const CLEARINGS := [[Vector2(14.0, -104.0), 8.5], [Vector2(-2.0, -80.0), 6.0], [Vector2(35.0, -90.0), 5.5]]
## Extra keep-out discs: the forest portal, Elowen, the encounter spawns, the edge gate.
const KEEP_OUT := [[Vector2(21.0, -99.0), 3.2], [Vector2(16.2, -102.4), 2.0], [Vector2(10.8, -97.0), 3.0],
		[Vector2(17.5, -105.5), 3.0], [Vector2(14.2, -52.5), 4.0]]
const EDGE_GATE := Vector3(14.4, 0.0, -51.8)

## model file, weight, scale min, scale max, trunk radius (model space)
const TREES := [
	["PineTree_1", 5, 1.2, 1.7, 0.35], ["PineTree_2", 5, 1.2, 1.7, 0.35], ["PineTree_3", 5, 1.2, 1.6, 0.35],
	["PineTree_4", 4, 1.1, 1.5, 0.35], ["PineTree_5", 4, 1.1, 1.5, 0.35],
	["CommonTree_1", 4, 1.1, 1.5, 0.35], ["CommonTree_2", 4, 1.1, 1.5, 0.35], ["CommonTree_3", 4, 1.1, 1.5, 0.35],
	["CommonTree_4", 4, 1.1, 1.5, 0.35], ["CommonTree_5", 3, 1.1, 1.5, 0.35],
	["BirchTree_1", 3, 1.1, 1.4, 0.25], ["BirchTree_2", 3, 1.1, 1.4, 0.25], ["BirchTree_3", 2, 1.1, 1.4, 0.25],
	["CommonTree_Autumn_1", 2, 1.1, 1.4, 0.35], ["CommonTree_Autumn_2", 2, 1.1, 1.4, 0.35],
	["BirchTree_Autumn_1", 2, 1.1, 1.4, 0.25], ["Willow_1", 1, 0.9, 1.1, 0.4], ["Willow_2", 1, 0.9, 1.1, 0.4],
	["BirchTree_Dead_1", 1, 1.0, 1.3, 0.25], ["Willow_Dead_1", 1, 0.9, 1.1, 0.35],
]
const TREE_SPACING := 2.4
## Trunks stay this far beyond a path's edge (paths are 2.0-2.8 m wide).
const PATH_CLEARANCE := 1.7
## Horizontal direction towards the isometric camera (IsoCameraRig yaw 45 degrees). A canopy
## standing on this side of a path would hide the courier walking it, so trees keep
## CAMERA_SIDE_CLEARANCE from walkable ground in this direction.
const CAMERA_DIR := Vector2(0.7071, 0.7071)
const CAMERA_SIDE_CLEARANCE := 3.5

var rng := RandomNumberGenerator.new()
var root_node: Node3D
## [Vector2 centre, radius] of everything already standing (village colliders and new trees).
var obstacles: Array = []
var _cache := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rng.seed = SEED
	var village := (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	# The village instances this scene: don't keep clear of the previous run's trees.
	var previous := village.get_node_or_null(^"WhisperwoodForest")
	if previous != null:
		village.remove_child(previous)
		previous.free()
	root.add_child(village)
	await process_frame
	_collect_obstacles(village)
	village.queue_free()
	await process_frame

	root_node = Node3D.new()
	root_node.name = "WhisperwoodForest"
	_edge_gate()
	_trees()
	_props()
	_undergrowth()
	_atmosphere()
	for node in root_node.find_children("*", "", true, false):
		if node.owner == null:
			node.owner = root_node
	var packed := PackedScene.new()
	packed.pack(root_node)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := ResourceSaver.save(packed, OUT)
	print("whisperwood: %d trees, %d obstacles considered, saved err=%d" % [root_node.get_node("Trees").get_child_count(), obstacles.size(), err])
	root_node.free()
	quit()


func _collect_obstacles(village: Node) -> void:
	var area := WOOD.merge(OUTSKIRTS).grow(4.0)
	for node in village.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		var body := shape_node.get_parent()
		if not (body is StaticBody3D or body is CharacterBody3D) or shape_node.shape == null:
			continue
		if body.name in ["Ground", "Boundary"] or String(village.get_path_to(body)).begins_with("Boundary"):
			continue
		var xform := shape_node.global_transform
		var at := Vector2(xform.origin.x, xform.origin.z)
		if not area.has_point(at) or xform.origin.y < -2.0:
			continue
		var scale := xform.basis.get_scale().x
		var radius := 0.5
		var shape := shape_node.shape
		if shape is CylinderShape3D:
			radius = (shape as CylinderShape3D).radius * scale
		elif shape is CapsuleShape3D:
			radius = (shape as CapsuleShape3D).radius * scale
		elif shape is SphereShape3D:
			radius = (shape as SphereShape3D).radius * scale
		elif shape is BoxShape3D:
			var size := (shape as BoxShape3D).size * xform.basis.get_scale()
			radius = Vector2(size.x, size.z).length() * 0.5
		if radius > 12.0:
			continue
		obstacles.append([at, radius])
	for keep in KEEP_OUT:
		obstacles.append(keep)


## Distance from `p` to the edge of the nearest walkable ground (paths, clearings, glades);
## negative inside it.
func _open_distance(p: Vector2) -> float:
	var d := _polyline_distance(p, TRAIL) - 1.7
	d = minf(d, _polyline_distance(p, PASS_TRAIL) - 1.7)
	d = minf(d, _polyline_distance(p, GLADE_PATH) - 1.0)
	d = minf(d, _polyline_distance(p, HOLLOW_PATH) - 1.0)
	for clearing in CLEARINGS:
		d = minf(d, p.distance_to(clearing[0]) - float(clearing[1]))
	return d


func _polyline_distance(p: Vector2, points: Array) -> float:
	var best := INF
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


func _free_at(p: Vector2, radius: float) -> bool:
	for obstacle in obstacles:
		if p.distance_to(obstacle[0]) < radius + float(obstacle[1]):
			return false
	return true


## Tree density by distance from open ground and by depth into the wood.
func _tree_chance(p: Vector2, open: float) -> float:
	var chance := 0.35 if open < 4.0 else (0.7 if open < 9.0 else 0.92)
	if p.y > WOOD.end.y:
		# Outskirts: from a loose treeline at the wood's edge to the odd tree near the village.
		chance *= remap(p.y, WOOD.end.y, OUTSKIRTS.end.y, 0.45, 0.04)
	return chance


func _trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	root_node.add_child(trees)
	var total := 0
	for entry in TREES:
		total += int(entry[1])
	var area := WOOD.merge(OUTSKIRTS)
	var step := 2.2
	var z := area.position.y + 1.0
	var count := 0
	while z < area.end.y - 0.5:
		var x := area.position.x + 1.0
		while x < area.end.x - 1.0:
			var p := Vector2(x + rng.randf_range(-0.9, 0.9), z + rng.randf_range(-0.9, 0.9))
			x += step
			var open := _open_distance(p)
			if open < PATH_CLEARANCE or rng.randf() > _tree_chance(p, open):
				continue
			if _open_distance(p - CAMERA_DIR * CAMERA_SIDE_CLEARANCE) < 0.5:
				continue
			if not _free_at(p, TREE_SPACING * 0.5 + 0.6):
				continue
			var pick := rng.randi_range(1, total)
			var entry: Array = TREES[0]
			for candidate in TREES:
				pick -= int(candidate[1])
				if pick <= 0:
					entry = candidate
					break
			# Willows and dead trees belong by the glades and the clearing, not deep inside.
			var name: String = entry[0]
			if (name.begins_with("Willow") or name.contains("Dead")) and open > 6.0:
				entry = TREES[rng.randi_range(0, 9)]
				name = entry[0]
			var scale := rng.randf_range(float(entry[2]), float(entry[3]))
			trees.add_child(_tree(name, Vector3(p.x, 0.0, p.y), scale, float(entry[4]), count))
			obstacles.append([p, TREE_SPACING * 0.5])
			count += 1
		z += step


func _tree(model_name: String, at: Vector3, scale: float, trunk: float, index: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Tree%03d_%s" % [index, model_name]
	body.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale), at)
	var model := (_load(NATURE + model_name + ".fbx") as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	var shape := CollisionShape3D.new()
	shape.name = "Trunk"
	shape.shape = _trunk_shape(trunk)
	shape.position.y = 0.8
	body.add_child(shape)
	var occluder := OCCLUDER.new() as Node3D
	occluder.name = "CameraOccluder"
	# Wider than a village tree's: forest canopies overhang the paths.
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
	# Rocks and mossy logs off the paths, more of them deeper in; mushrooms under the trees.
	var placed := {"rock": 0, "log": 0, "mushrooms": 0, "glow": 0}
	var targets := {"rock": 26, "log": 12, "mushrooms": 22, "glow": 7}
	var radii := {"rock": 1.0, "log": 1.6, "mushrooms": 0.5, "glow": 0.5}
	for kind in ["log", "rock", "glow", "mushrooms"]:
		var tries := 0
		while int(placed[kind]) < int(targets[kind]) and tries < 4000:
			tries += 1
			var p := Vector2(rng.randf_range(WOOD.position.x + 1.0, WOOD.end.x - 1.0), rng.randf_range(WOOD.position.y + 1.0, WOOD.end.y + 3.0))
			var open := _open_distance(p)
			var min_open := 0.6 if kind in ["mushrooms", "glow"] else 1.2
			if open < min_open or (kind == "glow" and open > 5.0) or not _free_at(p, float(radii[kind])):
				continue
			var scene: String
			match kind:
				"rock": scene = ROCKS[rng.randi() % ROCKS.size()]
				"log": scene = LOG
				"mushrooms": scene = MUSHROOMS
				_: scene = MUSHROOMS_GLOW
			var node := (_load(scene) as PackedScene).instantiate() as Node3D
			node.name = "%s%02d" % [kind.capitalize().replace(" ", ""), int(placed[kind])]
			var s := rng.randf_range(0.8, 1.3) if kind == "rock" else 1.0
			node.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0.0, p.y))
			props.add_child(node)
			obstacles.append([p, float(radii[kind])])
			placed[kind] = int(placed[kind]) + 1
	print("props ", placed)


func _undergrowth() -> void:
	var group := Node3D.new()
	group.name = "Undergrowth"
	root_node.add_child(group)
	var area := WOOD.merge(OUTSKIRTS)
	# model, count, min open distance, max open distance, scale range, depth only
	var layers := [
		["Bush_1", 120, 1.0, 99.0, Vector2(0.9, 1.4)], ["Bush_2", 110, 1.0, 99.0, Vector2(0.9, 1.4)],
		["BushBerries_1", 45, 0.8, 8.0, Vector2(0.9, 1.2)], ["BushBerries_2", 45, 0.8, 8.0, Vector2(0.9, 1.2)],
		["Plant_1", 140, 0.3, 99.0, Vector2(0.9, 1.5)], ["Plant_2", 140, 0.3, 99.0, Vector2(0.9, 1.5)],
		["Plant_3", 110, 0.3, 99.0, Vector2(0.9, 1.4)], ["Plant_4", 90, 0.3, 99.0, Vector2(0.8, 1.3)],
		["Plant_5", 90, 0.3, 99.0, Vector2(0.8, 1.3)],
		["Grass", 220, -6.0, 3.0, Vector2(0.8, 1.3)], ["Grass_2", 200, -6.0, 4.0, Vector2(0.8, 1.3)],
		["Grass_Short", 260, -9.0, 99.0, Vector2(0.8, 1.2)], ["Flowers", 110, -6.0, 1.5, Vector2(0.8, 1.2)],
	]
	for layer in layers:
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < int(layer[1]) and tries < int(layer[1]) * 30:
			tries += 1
			var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			var open := _open_distance(p)
			var name: String = layer[0]
			if open < float(layer[2]) or open > float(layer[3]):
				continue
			# Plants and flowers stay on the path verges, not on the paths themselves.
			if _polyline_distance(p, TRAIL) < 1.9 or _polyline_distance(p, PASS_TRAIL) < 1.9 or _polyline_distance(p, GLADE_PATH) < 1.2 or _polyline_distance(p, HOLLOW_PATH) < 1.2:
				continue
			if p.y > WOOD.end.y and rng.randf() > remap(p.y, WOOD.end.y, OUTSKIRTS.end.y, 0.6, 0.1):
				continue
			if name.begins_with("Bush") and not _free_at(p, 0.4):
				continue
			if name.begins_with("Flowers") and CLEARINGS[0][0].distance_to(p) < 3.0:
				continue
			var scale_range: Vector2 = layer[4]
			var s := rng.randf_range(scale_range.x, scale_range.y)
			transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, 0.0, p.y)))
		var field := MultiMeshInstance3D.new()
		field.set_script(SCATTER)
		field.name = String(layer[0]).to_pascal_case()
		field.set(&"source", _load(NATURE + String(layer[0]) + ".fbx"))
		field.set(&"transforms", transforms)
		field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if String(layer[0]).begins_with("Grass") or String(layer[0]).begins_with("Flowers") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		group.add_child(field)


func _edge_gate() -> void:
	var gate := (_load(GATE) as PackedScene).instantiate() as Node3D
	gate.name = "EdgeGate"
	# The trail runs north (towards -Z) through the gate; the gate's passage is along its Z.
	var direction := (TRAIL[3] - TRAIL[2]).normalized()
	gate.transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), EDGE_GATE)
	root_node.add_child(gate)
	var signpost := (_load(SIGNPOST) as PackedScene).instantiate() as Node3D
	signpost.name = "EdgeSign"
	signpost.set(&"text", "Whisperwood")
	signpost.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-20.0)), EDGE_GATE + Vector3(3.4, 0.0, 1.6))
	root_node.add_child(signpost)
	obstacles.append([Vector2(EDGE_GATE.x, EDGE_GATE.z), 4.0])


func _atmosphere() -> void:
	var group := Node3D.new()
	group.name = "Atmosphere"
	root_node.add_child(group)
	var fog := FogVolume.new()
	fog.name = "WoodMist"
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var centre := WOOD.get_center()
	fog.position = Vector3(centre.x, 2.0, centre.y - 3.0)
	fog.size = Vector3(WOOD.size.x + 6.0, 5.0, WOOD.size.y - 2.0)
	var material := FogMaterial.new()
	material.density = 0.035
	material.albedo = Color(0.62, 0.74, 0.66)
	material.emission = Color(0.02, 0.035, 0.03)
	material.height_falloff = 0.35
	material.edge_fade = 0.35
	fog.material = material
	group.add_child(fog)
	var index := 0
	for clearing in CLEARINGS:
		group.add_child(_fireflies("Fireflies%d" % index, clearing[0], float(clearing[1])))
		index += 1
	group.add_child(_fireflies("FirefliesTrail", Vector2(15.5, -72.0), 7.0))


func _fireflies(node_name: String, centre: Vector2, radius: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = Vector3(centre.x, 1.3, centre.y)
	particles.amount = int(clampf(radius * 5.0, 16.0, 48.0))
	particles.lifetime = 6.0
	particles.preprocess = 6.0
	particles.visibility_aabb = AABB(Vector3(-radius - 2.0, -2.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 5.0, radius * 2.0 + 4.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := _cached_firefly_process(radius)
	particles.process_material = process
	particles.draw_pass_1 = _firefly_mesh()
	return particles


func _cached_firefly_process(radius: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(radius, 0.9, radius)
	process.gravity = Vector3.ZERO
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 3.0
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.15
	process.scale_min = 0.6
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	return process


func _firefly_mesh() -> QuadMesh:
	if not _cache.has("firefly"):
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.09, 0.09)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color(1.0, 0.95, 0.55)
		material.emission_enabled = true
		material.emission = Color(0.85, 1.0, 0.45)
		material.emission_energy_multiplier = 4.0
		mesh.material = material
		_cache["firefly"] = mesh
	return _cache["firefly"]


func _load(path: String) -> Resource:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]
