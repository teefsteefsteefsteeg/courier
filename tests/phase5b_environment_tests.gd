extends SceneTree
## Phase 5B environment checks: the dressing scenes are wired in, upgraded areas
## no longer show primitive placeholder meshes, the forest has its own look,
## new colliders stay off roads and gameplay spots, and the scene stays within a
## rendering budget. Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5b_environment_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
## Village-space spots new colliders must keep clear of (radius in metres).
const KEEP_CLEAR := 1.2
const MAX_TRIANGLES := 4000000
const MAX_LIGHTS := 80

var _failures: int = 0
var _passes: int = 0
var level: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	for i in 10:
		await process_frame

	_test_dressing_wired()
	_test_post_office()
	_test_alchemy_shop()
	_test_village_props()
	_test_forest()
	_test_clearances()
	_test_budget()

	print("\n=== Phase 5B environment tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -----------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


## Visible MeshInstance3Ds under `node` whose mesh is a Godot primitive (placeholder art).
func _visible_primitives(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.is_visible_in_tree() and mesh.mesh is PrimitiveMesh:
			out.append(mesh)
	return out


## Instanced imported models (FBX scene roots) under `node`.
func _model_count(node: Node) -> int:
	var count := 0
	for child in node.find_children("*", "Node3D", true, false):
		if child.scene_file_path.ends_with(".fbx"):
			count += 1
	return count


func _names(meshes: Array[MeshInstance3D]) -> String:
	return ", ".join(meshes.slice(0, 6).map(func(m: MeshInstance3D) -> String: return str(level.get_path_to(m))))


# --- tests -------------------------------------------------------------------

func _test_dressing_wired() -> void:
	print("[Dressing scenes]")
	for path in ["VillageDressing", "PostOffice/Dressing", "ForestEntrance/Dressing"]:
		_check(level.has_node(path) and _model_count(level.get_node(path)) > 30, "%s is instanced with real models (%d)" % [path, _model_count(level.get_node(path)) if level.has_node(path) else 0])


func _test_post_office() -> void:
	print("[Post office]")
	var office := level.get_node("PostOffice")
	for part in ["Building", "Counter", "MailShelves", "SortingTable", "MailSacks"]:
		var left := _visible_primitives(office.get_node(part)).filter(func(m: MeshInstance3D) -> bool: return not m.name.contains("Sign"))
		_check(left.is_empty(), "post office %s shows no primitive placeholders (%s)" % [part, _names(left)])
	_check(_model_count(office.get_node("Dressing")) > 100, "post office is built from >100 model pieces (%d)" % _model_count(office.get_node("Dressing")))
	# Gameplay pieces stay where quests expect them.
	for path in ["Markers/QuestBoardSpot/QuestBoard", "Markers/ParcelPickupSpot/DragonEggPickup", "Mailbox", "Building/WallEastAShape"]:
		_check(office.has_node(path), "post office keeps %s" % path)
	_check(not office.has_node("Phase3Showcase"), "the decorative cargo exhibit was removed (Phase 7)")
	var fader := level.get_node("OccluderFader") as OccluderFader
	_check(fader.interior_root == office, "post office interior still fades for the camera")


func _test_alchemy_shop() -> void:
	print("[Alchemy shop]")
	var shop := level.get_node("Buildings/AlchemyShop") as MedievalBuilding
	_check(shop != null, "AlchemyShop is a MedievalBuilding")
	if shop == null:
		return
	# Since Phase 5F the shop is a merged MegaKit assembly rather than one FBX model.
	_check(_visible_primitives(shop).is_empty() and (_model_count(shop) >= 1 or shop.has_node(^"Model/Merged")), "AlchemyShop is a real model, not primitive boxes")
	_check(shop.roof_color.b > shop.roof_color.g and shop.roof_color.r > shop.roof_color.g, "AlchemyShop keeps its purple roof identity (%s)" % shop.roof_color)
	var decor := level.get_node("VillageDressing/Alchemy")
	_check(decor.get_child_count() >= 3, "alchemy shop has magical dressing (%d pieces)" % decor.get_child_count())
	_check(_visible_primitives(level.get_node("Buildings/Cauldron")).is_empty(), "alchemist's cauldron uses the real model")


func _test_village_props() -> void:
	print("[Village props]")
	var props := level.get_node("Props")
	for prefix in ["Well", "Stall", "Lamp", "Bench", "Barrel", "Crate", "Mushrooms"]:
		var nodes := props.get_children().filter(func(n: Node) -> bool: return n.name.begins_with(prefix))
		var primitive := 0
		var models := 0
		for n in nodes:
			primitive += _visible_primitives(n).size()
			models += _model_count(n)
		_check(not nodes.is_empty() and primitive == 0 and models >= nodes.size(), "%s props use real models (%d nodes, %d models)" % [prefix, nodes.size(), models])
	var dressing := level.get_node("VillageDressing")
	# Since Phase 5E the plaza, market square and roads are painted by the village terrain
	# (see phase5e_village_tests.gd) instead of individual paving tiles and slabs.
	_check(_splat_weight(Vector2(0, 0), 2) > 0.9, "town square is paved (terrain flagstones)")
	_check(dressing.get_node("Market").get_child_count() >= 6, "market has extra produce, cart and fencing (%d)" % dressing.get_node("Market").get_child_count())
	_check(_splat_weight(Vector2(12, 1), 1) > 0.9 or _splat_weight(Vector2(12, 1), 2) > 0.9, "roads have stone paving (terrain cobbles)")
	var houses := level.get_node("Buildings").get_children().filter(func(n: Node) -> bool: return n is MedievalBuilding)
	var roofs := {}
	for house in houses:
		roofs[(house as MedievalBuilding).roof_color.to_html(false)] = true
	_check(roofs.size() >= 6, "houses have varied roof colours (%d)" % roofs.size())


func _test_forest() -> void:
	print("[Whisperwood]")
	var forest := level.get_node("ForestEntrance")
	var dressing := forest.get_node("Dressing")
	_check(_visible_primitives(forest.get_node("Gate")).filter(func(m: MeshInstance3D) -> bool: return m.name != "SignBoard").is_empty(), "forest gate is a stone arch, not primitive posts")
	_check(_visible_primitives(forest.get_node("StoneCircle")).is_empty() and _visible_primitives(forest.get_node("Crystals")).is_empty(), "stone circle and crystals use real models")
	_check(dressing.has_node("Landmarks/StagStatue"), "forest has a stag statue landmark")
	_check(dressing.get_node("Trees").get_child_count() >= 8, "forest is denser (%d extra trees)" % dressing.get_node("Trees").get_child_count())
	var undergrowth := 0
	for field in dressing.get_node("Undergrowth").get_children():
		undergrowth += (field as MultiMeshInstance3D).multimesh.instance_count
	_check(undergrowth >= 400, "forest floor has dense undergrowth (%d plants)" % undergrowth)
	var glow := dressing.get_node("Details").get_children().filter(func(n: Node) -> bool: return n.name.begins_with("GlowShrooms"))
	_check(glow.size() >= 10, "forest has glowing magical plants (%d)" % glow.size())
	_check(dressing.find_children("*", "FogVolume", true, false).size() >= 1 and dressing.find_children("*", "GPUParticles3D", true, false).size() >= 1, "forest has mist and fireflies")
	var env := (level.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.volumetric_fog_enabled and is_zero_approx(env.volumetric_fog_density), "fog is local to the forest (global density 0)")
	# Since Phase 5E the forest floor is a channel of the village terrain splat, blended softly into the meadow.
	_check(_splat_weight(Vector2(6, -66), 0, "b") > 0.9 and _splat_weight(Vector2(-20, 10), 0, "b") < 0.1, "forest floor has its own darker ground")


## Weight of one splat channel (0 = R .. 3 = A) of the village terrain at a village XZ position.
func _splat_weight(at: Vector2, channel: int, map := "a") -> float:
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/terrain/village_splat_%s.png" % map))
	var material := load("res://assets/materials/environment/village_ground.tres") as ShaderMaterial
	var origin: Vector2 = material.get_shader_parameter(&"splat_origin")
	var size: float = material.get_shader_parameter(&"splat_size")
	return image.get_pixelv(Vector2i(((at - origin) / size * image.get_width()).floor()))[channel]


func _test_clearances() -> void:
	print("[Clearances]")
	var spots: Array[Node3D] = []
	for node in level.find_children("*", "Marker3D", true, false) + level.get_node("NPCs").get_children():
		spots.append(node as Node3D)
	var paths: Array[MeshInstance3D] = []
	for node in level.get_node("Paths").get_children():
		if node.name != "Square":
			paths.append(node as MeshInstance3D)
	paths.append(level.get_node("ForestEntrance/Path") as MeshInstance3D)
	var bad: Array[String] = []
	var checked := 0
	for dressing_path in ["VillageDressing", "ForestEntrance/Dressing"]:
		for shape in level.get_node(dressing_path).find_children("*", "CollisionShape3D", true, false):
			checked += 1
			var at := (shape as Node3D).global_position
			for spot in spots:
				var flat := spot.global_position - at
				flat.y = 0
				if flat.length() < KEEP_CLEAR:
					bad.append("%s near %s" % [level.get_path_to(shape.get_parent()), spot.name])
			for path in paths:
				var local := path.global_transform.affine_inverse() * at
				var half := path.mesh.get_aabb().size * 0.5
				if absf(local.x) < half.x and absf(local.z) < half.z:
					bad.append("%s on %s" % [level.get_path_to(shape.get_parent()), path.name])
	_check(checked > 50 and bad.is_empty(), "%d new colliders stay off roads and gameplay spots %s" % [checked, bad.slice(0, 5)])


func _test_budget() -> void:
	print("[Rendering budget]")
	var triangles := 0
	var meshes := 0
	for node in level.find_children("*", "GeometryInstance3D", true, false):
		if not (node as Node3D).is_visible_in_tree():
			continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			meshes += 1
			triangles += _mesh_triangles((node as MeshInstance3D).mesh)
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multi := (node as MultiMeshInstance3D).multimesh
			triangles += _mesh_triangles(multi.mesh) * multi.instance_count
	var lights := level.find_children("*", "Light3D", true, false).size()
	print("  visible meshes %d, triangles %d, lights %d" % [meshes, triangles, lights])
	_check(triangles < MAX_TRIANGLES, "scene triangles within budget (%d < %d)" % [triangles, MAX_TRIANGLES])
	_check(lights < MAX_LIGHTS, "light count within budget (%d < %d)" % [lights, MAX_LIGHTS])


static func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var index = arrays[Mesh.ARRAY_INDEX]
		total += (index.size() if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total
