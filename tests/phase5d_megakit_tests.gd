extends SceneTree
## Phase 5D MegaKit pilot checks: only the approved 25 models are imported (with
## their licences), textures are capped, the four pilot locations are dressed,
## new colliders keep roads and gameplay spots clear, and the pilot stays cheap.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5d_megakit_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const MEGAKIT := "res://assets/models/megakit"
const EXPECTED_MODELS := 25
const MAX_TEXTURE_SIZE := 1024
const KEEP_CLEAR := 1.2
## Post office south doorway (village XZ) and the approach to it.
const DOORWAY := Rect2(-13.5, -1.2, 3.0, 4.0)
const MAX_PILOT_NODES := 90
const MAX_PILOT_TRIANGLES := 150000

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var pilot: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_imports()
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	for i in 10:
		await process_frame
	pilot = level.get_node_or_null("MegaKitPilotDressing") as Node3D
	_check(pilot != null, "village instances the MegaKit pilot dressing")
	if pilot != null:
		_test_locations()
		_test_clearances()
		_test_budget()
	_test_untouched()
	print("\n=== Phase 5D MegaKit tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _test_imports() -> void:
	print("[Imports and licences]")
	var models: Array[String] = []
	for pack in ["village", "nature"]:
		var dir := MEGAKIT.path_join(pack)
		_check(FileAccess.file_exists(dir.path_join("License_Standard.txt")) and FileAccess.get_file_as_string(dir.path_join("License_Standard.txt")).contains("CC0"), "%s keeps its CC0 License_Standard.txt" % pack)
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gltf"):
				models.append(dir.path_join(file))
			elif file.ends_with(".png"):
				var texture := load(dir.path_join(file)) as Texture2D
				_check(texture != null and maxi(texture.get_width(), texture.get_height()) <= MAX_TEXTURE_SIZE, "%s capped at %d px (%s)" % [file, MAX_TEXTURE_SIZE, Vector2i(texture.get_width(), texture.get_height()) if texture else "missing"])
	_check(models.size() == EXPECTED_MODELS, "exactly %d MegaKit models imported (%d)" % [EXPECTED_MODELS, models.size()])
	var scene_text := ""
	for dir in ["res://scenes/props/megakit", "res://scenes/environment"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tscn"):
				scene_text += FileAccess.get_file_as_string(dir.path_join(file))
	var unused := models.filter(func(path: String) -> bool: return not scene_text.contains(path))
	_check(unused.is_empty(), "every imported model is used (%s unused)" % [unused])
	for path in models:
		_check(load(path) is PackedScene, "%s loads" % path.get_file())


func _test_locations() -> void:
	print("[Pilot locations]")
	var office := pilot.get_node("PostOffice")
	var vines := office.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Vine"))
	_check(vines.size() >= 5, "post office has climbing vines (%d)" % vines.size())
	_check(office.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("BedPlant")).size() >= 5, "post office has planted flower beds")
	for house in ["Rose", "Fern"]:
		var parts := pilot.get_node("Houses").get_children().filter(func(n: Node) -> bool: return n.name.begins_with(house))
		_check(parts.size() >= 5, "Cottage%s has vines, bed edging and plants (%d)" % [house, parts.size()])
	var farm := pilot.get_node("Farm")
	_check(farm.has_node("Wagon") and farm.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("FieldFence")).size() >= 2, "farm edge has the wagon and wooden fences")
	var stones := 0
	for node in pilot.get_node("ForestPath").get_children():
		if node.name.begins_with("SteppingStones"):
			stones += (node as MultiMeshInstance3D).multimesh.instance_count
	_check(stones >= 6, "forest path has stepping stones (%d)" % stones)
	var path := pilot.get_node("ForestPath")
	_check(path.has_node("Mushrooms") and path.has_node("PathPebbles") and path.has_node("GroundPlants"), "forest path has mushrooms, pebbles and ground plants")
	_check(path.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("PathBoulder")).size() >= 1, "forest path has boulders")


func _test_clearances() -> void:
	print("[Clearances]")
	var spots: Array[Node3D] = []
	for node in level.find_children("*", "Marker3D", true, false) + level.get_node("NPCs").get_children():
		spots.append(node as Node3D)
	var roads: Array[MeshInstance3D] = []
	for node in level.get_node("Paths").get_children():
		if node.name != "Square":
			roads.append(node as MeshInstance3D)
	roads.append(level.get_node("ForestEntrance/Path") as MeshInstance3D)
	var shapes := pilot.find_children("*", "CollisionShape3D", true, false)
	var bad: Array[String] = []
	for shape in shapes:
		var at := (shape as Node3D).global_position
		for spot in spots:
			if Vector2(at.x - spot.global_position.x, at.z - spot.global_position.z).length() < KEEP_CLEAR:
				bad.append("%s near %s" % [shape.get_parent().name, spot.name])
		for road in roads:
			var local := road.global_transform.affine_inverse() * at
			var half := road.mesh.get_aabb().size * 0.5
			if absf(local.x) < half.x and absf(local.z) < half.z:
				bad.append("%s on %s" % [shape.get_parent().name, road.name])
		if Vector2(at.x, at.z).length() < 7.0:
			bad.append("%s on the town square" % shape.get_parent().name)
	_check(not shapes.is_empty() and bad.is_empty(), "%d pilot colliders stay off roads, the square and gameplay spots %s" % [shapes.size(), bad])
	var blocking := []
	for node in pilot.find_children("*", "Node3D", true, false):
		var p := (node as Node3D).global_position
		if node.get_parent().get_parent() == pilot and DOORWAY.has_point(Vector2(p.x, p.z)):
			blocking.append(node.name)
	_check(blocking.is_empty(), "post office south doorway stays open %s" % [blocking])
	var decorative := pilot.find_children("Vine*", "", true, false) + pilot.find_children("Bed*", "", true, false)
	_check(decorative.all(func(n: Node) -> bool: return n.find_children("*", "CollisionShape3D", true, false).is_empty()), "vines, flowers and bed edging have no collision")


func _test_budget() -> void:
	print("[Pilot budget]")
	var nodes := 0
	var triangles := 0
	for node in pilot.find_children("*", "GeometryInstance3D", true, false):
		nodes += 1
		if node is MeshInstance3D:
			triangles += _triangles((node as MeshInstance3D).mesh)
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multi := (node as MultiMeshInstance3D).multimesh
			triangles += _triangles(multi.mesh) * multi.instance_count
	print("  pilot geometry nodes %d, triangles %d" % [nodes, triangles])
	_check(nodes <= MAX_PILOT_NODES, "pilot adds at most %d geometry nodes (%d)" % [MAX_PILOT_NODES, nodes])
	_check(triangles <= MAX_PILOT_TRIANGLES, "pilot adds at most %d triangles (%d)" % [MAX_PILOT_TRIANGLES, triangles])
	_check(pilot.find_children("*", "Light3D", true, false).is_empty(), "pilot adds no lights")


func _test_untouched() -> void:
	print("[Existing work untouched]")
	for path in ["Buildings/CottageRose", "Buildings/CottageFern", "Buildings/AlchemyShop", "PostOffice/Dressing", "VillageDressing", "ForestEntrance/Dressing"]:
		_check(level.has_node(path), "%s still present" % path)
	var player_model := level.get_node("Player/Visual/Character") as KayKitCharacter
	_check(player_model != null and player_model.model.resource_path.ends_with("Ranger.glb"), "Phase 5C courier model unchanged")


static func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var index = arrays[Mesh.ARRAY_INDEX]
		total += (index.size() if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total
