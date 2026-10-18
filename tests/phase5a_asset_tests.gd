extends SceneTree
## Phase 5A real-asset checks: imported Quaternius models load within budget, the
## village / forest props use them, colliders are no larger than the placeholders
## they replaced, and the player can still walk to every quest location.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5a_asset_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const MODEL_DIRS := ["res://assets/models/quaternius/medieval_village", "res://assets/models/quaternius/ultimate_nature"]
## Raised from 10k in Phase 5B for the single Bell_Tower landmark (11.8k).
const MAX_TRIS_BUILDING := 12000
const MAX_TRIS_NATURE := 3500
## Placeholder footprints the new props must not exceed (half-extents in metres).
const COTTAGE_HALF := Vector2(3.2, 2.7)
const TREE_RADIUS := 0.4
const ROCK_RADIUS := 0.85
const REPLACED_HOUSES := ["CottageRose", "CottageOak", "CottageFern", "CottageBlue", "CottageMill",
		"CottageHill", "CottageWillow", "CottageBrook", "CottageMoss"]
## Walk targets, each reached from the village square by steering straight at it
## through the listed waypoints (roads, not across lawns).
const ROUTES := {
	"NPCs/MerchantMira": [Vector3(2, 0, 0)],
	"NPCs/AlchemistCorvin": [Vector3(2, 0, 0), Vector3(5, 0, 3), Vector3(9.5, 0, 6), Vector3(9.5, 0, 17)],
	"NPCs/VillagerPip": [Vector3(2, 0, 0)],
	"Markers/MarketDeliverySpot": [Vector3(2, 0, 0)],
	"Markers/AlchemyDeliverySpot": [Vector3(2, 0, 0), Vector3(5, 0, 3), Vector3(9.5, 0, 6), Vector3(9.5, 0, 17)],
	"PostOffice/Markers/QuestBoardSpot": [Vector3(2, 0, 0), Vector3(-3, 0, -5.6), Vector3(-9, 0, -5.6)],
	"ForestEntrance/Markers/ForestClearingSpot": [Vector3(2, 0, 0)],
	"NPCs/MageElowen": [Vector3(2, 0, 0)],
}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_model_budget()
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _frames(20)

	_test_houses()
	_test_trees()
	_test_rocks_and_bushes()
	await _test_routes()

	print("\n=== Phase 5A asset tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -----------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _triangles(node: Node) -> int:
	var tris := 0
	for m in _meshes(node):
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += (index.size() if not index.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return tris


## True if `node` is an instance of a Phase 5A real-asset prop scene.
func _uses_real_model(node: Node, folder: String) -> bool:
	return node.scene_file_path.begins_with("res://scenes/props/%s/" % folder) and node.has_node(^"Model") \
			and node.get_node(^"Model").scene_file_path.ends_with(".fbx")


func _real_materials(node: Node) -> bool:
	var meshes := _meshes(node)
	if meshes.is_empty():
		return false
	for m in meshes:
		if m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
		for s in m.mesh.get_surface_count():
			if m.get_active_material(s) == null:
				return false
	return true


func _collider(body: Node) -> CollisionShape3D:
	return body.get_node_or_null(^"CollisionShape3D") as CollisionShape3D


# --- tests -------------------------------------------------------------------

func _test_model_budget() -> void:
	print("[Imported models]")
	for dir in MODEL_DIRS:
		_check(FileAccess.file_exists(dir + "/License.txt"), "%s ships its License.txt" % dir.get_file())
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".fbx"):
				continue
			var scene := load(dir + "/" + file) as PackedScene
			_check(scene != null, "%s imports" % file)
			if scene == null:
				continue
			var inst := scene.instantiate()
			var tris := _triangles(inst)
			var budget := MAX_TRIS_BUILDING if dir.ends_with("medieval_village") else MAX_TRIS_NATURE
			_check(tris > 0 and tris <= budget, "%s within polygon budget (%d / %d tris)" % [file, tris, budget])
			inst.free()


func _test_houses() -> void:
	print("[Medieval houses]")
	for house_name in REPLACED_HOUSES:
		var house := level.get_node("Buildings/" + house_name)
		_check(_uses_real_model(house, "medieval"), "%s uses a Medieval Village model" % house_name)
		_check(_real_materials(house), "%s keeps imported materials and casts shadows" % house_name)
		var box := _collider(house).shape as BoxShape3D
		_check(box != null and box.size.x / 2 <= COTTAGE_HALF.x and box.size.z / 2 <= COTTAGE_HALF.y,
				"%s collider fits the old cottage footprint (%s)" % [house_name, box.size if box else Vector3.ZERO])
		var aabb := _world_aabb(house)
		_check(aabb.size.x / 2 <= COTTAGE_HALF.x + 0.1 and aabb.size.z / 2 <= COTTAGE_HALF.y + 0.1 and aabb.position.y > -0.05,
				"%s model sits on the ground inside the old footprint (%s)" % [house_name, aabb.size])
		_check(house.get_node_or_null(^"CameraOccluder") is CameraOccluder, "%s still fades for the camera" % house_name)
	var shop := level.get_node("Buildings/AlchemyShop")
	_check(shop is MedievalBuilding and _uses_real_model(shop, "medieval"), "AlchemyShop is a recoloured Medieval Village model")


func _world_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(node):
		var local := node.global_transform.affine_inverse() * m.global_transform * m.mesh.get_aabb()
		out = local if first else out.merge(local)
		first = false
	return out


func _test_trees() -> void:
	print("[Nature trees]")
	for group_path in ["Trees", "ForestEntrance/Trees"]:
		var trees := level.get_node(group_path).get_children()
		var real := trees.filter(func(t: Node) -> bool: return _uses_real_model(t, "nature"))
		_check(real.size() == trees.size(), "%s: all %d trees use Ultimate Nature models (%d)" % [group_path, trees.size(), real.size()])
		var ok := true
		for t in real:
			var shape := _collider(t).shape as CylinderShape3D
			ok = ok and shape != null and shape.radius <= TREE_RADIUS + 0.001 and _real_materials(t) \
					and t.get_node_or_null(^"CameraOccluder") is CameraOccluder
		_check(ok, "%s: trunk colliders unchanged, materials and occluders intact" % group_path)


func _test_rocks_and_bushes() -> void:
	print("[Nature rocks and bushes]")
	var rocks := level.get_node("Props").get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Rock"))
	_check(rocks.size() == 7, "seven village rocks (%d)" % rocks.size())
	for rock in rocks:
		var shape := _collider(rock).shape as CylinderShape3D
		_check(_uses_real_model(rock, "nature") and shape != null and shape.radius <= ROCK_RADIUS,
				"%s uses a real rock with a collider no wider than before" % rock.name)
	for parent in ["Props", "ForestEntrance"]:
		var bushes := level.get_node(parent).find_children("Bush*", "", false, false)
		var real := bushes.filter(func(n: Node) -> bool: return _uses_real_model(n, "nature") and _real_materials(n))
		_check(not bushes.is_empty() and real.size() == bushes.size(), "%s: all %d bushes use Ultimate Nature models" % [parent, bushes.size()])


func _test_routes() -> void:
	print("[Player navigation]")
	for target_path in ROUTES:
		var target := (level.get_node(target_path) as Node3D).global_position
		player.teleport_to(Vector3(2, 0, 0))
		rig.snap_to_target()
		await _frames(5)
		var reached := true
		for waypoint in ROUTES[target_path] + [target]:
			reached = reached and await _steer_to(waypoint, 1.6, 900)
		_check(reached, "player walks from the square to %s (stopped at %s)" % [target_path, player.global_position.snapped(Vector3.ONE * 0.1)])


## Steers the player toward `goal` with analog input. Returns false if it does
## not get within `radius` metres in `max_frames`.
func _steer_to(goal: Vector3, radius: float, max_frames: int) -> bool:
	var stuck := 0
	var last := player.global_position
	for i in max_frames:
		var to := goal - player.global_position
		to.y = 0
		if to.length() <= radius:
			break
		# Invert the camera-relative mapping: find input whose world direction matches.
		var right := player.camera_relative_direction(Vector2.RIGHT)
		var back := player.camera_relative_direction(Vector2.DOWN)
		var dir := to.normalized()
		var x := dir.dot(right)
		var y := dir.dot(back)
		_press(&"move_right", &"move_left", x)
		_press(&"move_back", &"move_forward", y)
		await physics_frame
		if i % 60 == 59:
			stuck = stuck + 1 if player.global_position.distance_to(last) < 0.3 else 0
			last = player.global_position
			if stuck >= 2:
				break
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)
	var flat := goal - player.global_position
	flat.y = 0
	return flat.length() <= radius


func _press(positive: StringName, negative: StringName, amount: float) -> void:
	Input.action_release(positive)
	Input.action_release(negative)
	if amount > 0.05:
		Input.action_press(positive, amount)
	elif amount < -0.05:
		Input.action_press(negative, -amount)
