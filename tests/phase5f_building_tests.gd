extends SceneTree
## Phase 5F building visual checks: the eleven village buildings are distinct
## Medieval Village MegaKit assemblies, keep the exact collider and placement of
## the buildings they replace, merge into a few draw calls, use the shared
## building materials, still fade for the camera, and the kit stays lean.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5f_building_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const KIT := "res://assets/models/megakit/buildings"
const TEXTURES := "res://assets/textures/buildings"
const MATERIALS := "res://assets/materials/buildings/"
const BUILDINGS := "res://scenes/buildings"
## The bell tower's bell keeps its Quaternius model and materials.
const BELL := "res://assets/models/quaternius/medieval_village/Bell.fbx"
const MAX_TEXTURE_SIZE := 1024
## Node -> [scene, position, yaw (degrees), collider size, collider centre y]. Positions,
## yaws and colliders are those of Phase 5E (colliders from the Phase 5A/5B scenes), except
## the four buildings the Phase 5H spacing pass moved (Oak, Fern, Blue, the bell tower).
const EXPECTED := {
	"Buildings/AlchemyShop": ["alchemy_shop", Vector3(4, 0, 12), 0.0, Vector3(3.0965, 3.2, 4.77), 1.6],
	"Buildings/CottageRose": ["rose_cottage", Vector3(-8, 0, 13), 0.0, Vector3(3.852, 3.2, 4.788), 1.6],
	"Buildings/CottageOak": ["oak_house", Vector3(-19.6, 0, 10.6), 180.0, Vector3(3.197, 3.2, 4.925), 1.6],
	"Buildings/CottageFern": ["fern_cottage", Vector3(19.8, 0, 14.2), 180.0, Vector3(3.852, 3.2, 4.788), 1.6],
	"Buildings/CottageBlue": ["blue_house", Vector3(-8.6, 0, -20.2), 0.0, Vector3(3.197, 3.2, 4.925), 1.6],
	"Buildings/CottageMill": ["mill", Vector3(25, 0, -6), 0.0, Vector3(3.305, 3.2, 4.423), 1.6],
	"Buildings/CottageHill": ["blacksmith", Vector3(-26, 0, -4), 0.0, Vector3(5.602, 3.2, 4.723), 1.6],
	"Buildings/CottageWillow": ["inn", Vector3(-22, 0, 22), 90.0, Vector3(4.896, 3.2, 4.884), 1.6],
	"Buildings/CottageBrook": ["brook_cottage", Vector3(14, 0, 26), 180.0, Vector3(3.197, 3.2, 4.925), 1.6],
	"Buildings/CottageMoss": ["moss_cottage", Vector3(-6, 0, 27), 180.0, Vector3(3.852, 3.2, 4.788), 1.6],
	"VillageDressing/Landmarks/BellTower": ["bell_tower", Vector3(-1.4, 0, -10.4), 0.0, Vector3(3.1125, 3.0, 3.5811), 1.5],
}
## One surface per shared material at most (timber, planks, plaster, roof, stone,
## uneven brick, brick, iron, glass, embers).
const MAX_SURFACES := 10
const MAX_TRIANGLES_PER_BUILDING := 45000
const MAX_TRIANGLES_TOTAL := 300000
## Eaves, balconies, porches and the mill's sails may reach past the collider.
const OVERHANG := 2.6

var _failures: int = 0
var _passes: int = 0
var level: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_kit()
	_test_distinct()
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	for i in 10:
		await process_frame
	_test_placement()
	_test_merged()
	await _test_mill_and_fading()
	print("\n=== Phase 5F building tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


# --- tests -------------------------------------------------------------------

func _test_kit() -> void:
	print("[MegaKit building kit]")
	_check(FileAccess.get_file_as_string(KIT.path_join("License_Standard.txt")).contains("CC0"), "kit keeps its CC0 License_Standard.txt")
	var models: Array[String] = []
	for file in DirAccess.get_files_at(KIT):
		if file.ends_with(".gltf"):
			models.append(KIT.path_join(file))
	var scene_text := ""
	for file in DirAccess.get_files_at(BUILDINGS):
		if file.ends_with(".tscn"):
			scene_text += FileAccess.get_file_as_string(BUILDINGS.path_join(file))
	var unused := models.filter(func(path: String) -> bool: return not scene_text.contains(path))
	_check(models.size() >= 30 and unused.is_empty(), "%d kit pieces, every one used by a building (%s unused)" % [models.size(), unused])
	var external := true
	for path in models:
		var piece := (load(path) as PackedScene).instantiate()
		for mesh in piece.find_children("*", "MeshInstance3D", true, false):
			for s in (mesh as MeshInstance3D).mesh.get_surface_count():
				var material := (mesh as MeshInstance3D).mesh.surface_get_material(s)
				external = external and material != null and material.resource_path.begins_with(MATERIALS)
		piece.free()
	_check(external, "every kit material maps to a shared material in %s" % MATERIALS)
	for file in DirAccess.get_files_at(TEXTURES):
		if file.ends_with(".png"):
			var texture := load(TEXTURES.path_join(file)) as Texture2D
			_check(texture != null and maxi(texture.get_width(), texture.get_height()) <= MAX_TEXTURE_SIZE, "%s capped at %d px" % [file, MAX_TEXTURE_SIZE])


func _test_distinct() -> void:
	print("[Distinct buildings]")
	var signatures := {}
	for path in EXPECTED:
		var scene_name: String = EXPECTED[path][0]
		var building := (load("%s/%s.tscn" % [BUILDINGS, scene_name]) as PackedScene).instantiate()
		var pieces: Array[String] = []
		for child in building.get_node(^"Model").get_children():
			pieces.append(child.scene_file_path.get_file() if not child.scene_file_path.is_empty() else String(child.name))
		pieces.sort()
		var signature := ",".join(pieces)
		_check(pieces.size() >= 20, "%s is assembled from %d kit pieces" % [scene_name, pieces.size()])
		_check(not signatures.has(signature), "%s has its own design (not a copy of %s)" % [scene_name, signatures.get(signature, "-")])
		signatures[signature] = scene_name
		building.free()


func _test_placement() -> void:
	print("[Placement and collision unchanged]")
	var roofs := {}
	for path in EXPECTED:
		var spec: Array = EXPECTED[path]
		var building := level.get_node_or_null(path) as MedievalBuilding
		_check(building != null and building.scene_file_path == "%s/%s.tscn" % [BUILDINGS, spec[0]], "%s uses scenes/buildings/%s.tscn" % [path, spec[0]])
		if building == null:
			continue
		var yaw := rad_to_deg(building.global_basis.get_euler().y)
		_check(building.global_position.is_equal_approx(spec[1]) and absf(angle_difference(deg_to_rad(yaw), deg_to_rad(spec[2]))) < 0.01,
				"%s keeps its expected position and facing" % path)
		var shape := building.get_node(^"CollisionShape3D") as CollisionShape3D
		var box := shape.shape as BoxShape3D
		_check(box != null and box.size.is_equal_approx(spec[3]) and shape.position.is_equal_approx(Vector3(0, spec[4], 0)),
				"%s keeps its collider (%s)" % [path, box.size if box else Vector3.ZERO])
		var bounds := _bounds(building)
		var half := Vector2(spec[3].x, spec[3].z) * 0.5
		_check(bounds.position.y > -0.3 and absf(bounds.position.x) <= half.x + OVERHANG and absf(bounds.position.z) <= half.y + OVERHANG
				and bounds.end.x <= half.x + OVERHANG and bounds.end.z <= half.y + OVERHANG,
				"%s sits on the ground around its collider (%s)" % [path, bounds])
		if path.begins_with("Buildings/"):
			roofs[building.roof_color.to_html(false)] = true
	_check(roofs.size() == 10, "every village building has its own roof colour (%d)" % roofs.size())


func _test_merged() -> void:
	print("[Merged meshes and materials]")
	var total := 0
	for path in EXPECTED:
		var building := level.get_node(path) as MedievalBuilding
		var meshes := building.find_children("*", "MeshInstance3D", true, false)
		var surfaces := 0
		var triangles := 0
		var shared := true
		var shadows := true
		var primitives := 0
		for node in meshes:
			var mesh := node as MeshInstance3D
			if mesh.mesh is PrimitiveMesh:
				primitives += 1
			shadows = shadows and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in mesh.mesh.get_surface_count():
				surfaces += 1
				triangles += mesh.mesh.surface_get_array_index_len(s) / 3
				var source := mesh.mesh.surface_get_material(s)
				shared = shared and source != null and (source.resource_path.begins_with(MATERIALS) or source.resource_path.begins_with(BELL))
		total += triangles
		var limit := MAX_SURFACES * (2 if building.has_node(^"Sails") else 1)
		_check(meshes.size() <= 2 and surfaces <= limit and primitives == 0,
				"%s merged to %d meshes / %d surfaces" % [path, meshes.size(), surfaces])
		_check(shared and shadows, "%s draws with the shared building materials and casts shadows" % path)
		_check(triangles <= MAX_TRIANGLES_PER_BUILDING, "%s within %d triangles (%d)" % [path, MAX_TRIANGLES_PER_BUILDING, triangles])
		var occluder := building.get_node_or_null(^"CameraOccluder") as CameraOccluder
		_check(occluder != null and occluder.height >= _bounds(building).end.y - 1.0, "%s camera occluder covers its height" % path)
	_check(total <= MAX_TRIANGLES_TOTAL, "all buildings within %d triangles (%d)" % [MAX_TRIANGLES_TOTAL, total])
	var shop := level.get_node("Buildings/AlchemyShop") as MedievalBuilding
	var glow := false
	var mesh := shop.get_node(^"Model/Merged") as MeshInstance3D
	for s in mesh.mesh.get_surface_count():
		var override := mesh.get_surface_override_material(s) as BaseMaterial3D
		if override != null and override.emission_enabled and override.emission.b > override.emission.g:
			glow = true
	_check(glow, "alchemy shop windows glow violet")


func _test_mill_and_fading() -> void:
	print("[Mill sails and camera fading]")
	var sails := level.get_node("Buildings/CottageMill/Sails") as Node3D
	var before := sails.basis
	for i in 20:
		await process_frame
	_check(sails is Spinner and not sails.basis.is_equal_approx(before), "mill sails turn")
	# Stand the courier just behind Rose Cottage as seen from the camera.
	var house := level.get_node("Buildings/CottageRose") as MedievalBuilding
	var camera := (level.get_node("IsoCameraRig") as IsoCameraRig).camera
	var away := -camera.global_basis.z
	away = Vector3(away.x, 0, away.z).normalized()
	(level.get_node("Player") as PlayerController).teleport_to(house.global_position + away * 3.6)
	for i in 40:
		await physics_frame
	var merged := house.get_node(^"Model/Merged") as MeshInstance3D
	_check(merged.transparency > 0.5, "merged house fades when it hides the courier (%.2f)" % merged.transparency)


## Bounds of the building's meshes in its own space.
func _bounds(building: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := building.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
