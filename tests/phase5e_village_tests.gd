extends SceneTree
## Phase 5E village overhaul checks: the painted terrain replaces the flat
## planes, every road and lane in the layout is walkable end to end, houses
## face their lanes, nothing solid stands in a road, the walkable area stays
## flat while hills rise outside the walls, and gameplay spots are unchanged.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5e_village_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const LAYOUT := "res://assets/textures/terrain/village_layout.json"
const SPLAT_A := "res://assets/textures/terrain/village_splat_a.png"
const SPLAT_B := "res://assets/textures/terrain/village_splat_b.png"
## Houses turned to face their lane in Phase 5E, and the lane end they face.
const FACING := {
	"CottageOak": Vector2(-17, 5.0), "CottageMoss": Vector2(-6, 21.2), "CottageBrook": Vector2(14, 21.4),
	"CottageFern": Vector2(17.6, 6.0), "CottageWillow": Vector2(-18, 22.0), "CottageRose": Vector2(-8, 21.0),
	"CottageBlue": Vector2(-5.6, -10.4), "CottageHill": Vector2(-26, 3.2),
}
## Gameplay positions that must not move (village XZ), from Phase 4/5A.
const SPOTS := {
	"Markers/MarketDeliverySpot": Vector2(11, 0.4), "Markers/AlchemyDeliverySpot": Vector2(6, 18.6),
	"NPCs/MerchantMira": Vector2(11, -1.3), "NPCs/AlchemistCorvin": Vector2(6.4, 16.9), "NPCs/VillagerPip": Vector2(2.6, 2.6),
	"NPCs/PostmasterBram": Vector2(-15, -8.3), "NPCs/MageElowen": Vector2(16.2, -32.4),
	"ForestEntrance/Markers/ForestClearingSpot": Vector2(14, -31.2),
}
## Solid things allowed in a road core by design: Corvin waits at the end of the
## road outside his shop, and the forest gate posts frame the forest path.
const ROAD_EXCEPTIONS := ["NPCs/AlchemistCorvin", "ForestEntrance/Gate"]
## The south road ends at the alchemy shop behind Corvin; walks stop in front of him.
const WALK_ENDS := {"south": Vector2(8.6, 17.0)}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var layout: Dictionary
var splat_a: Image
var splat_b: Image


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	splat_a = Image.load_from_file(ProjectSettings.globalize_path(SPLAT_A))
	splat_b = Image.load_from_file(ProjectSettings.globalize_path(SPLAT_B))
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	for i in 10:
		await physics_frame

	_test_terrain()
	_test_surfaces()
	_test_houses()
	_test_roads_clear()
	_test_spots_unchanged()
	await _test_walks()

	print("\n=== Phase 5E village tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


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


func _splat(image: Image, at: Vector2) -> Color:
	var px := Vector2i(((at + Vector2(64, 64)) / 128.0 * image.get_width()).floor())
	px = px.clamp(Vector2i.ZERO, Vector2i(image.get_width() - 1, image.get_height() - 1))
	return image.get_pixelv(px)


func _points(name: String) -> Array[Vector2]:
	var source: Dictionary = layout["cobble"] if (layout["cobble"] as Dictionary).has(name) else layout["dirt"]
	var out: Array[Vector2] = []
	for p in source[name]:
		out.append(Vector2(p[0], p[1]))
	return out


# --- tests -------------------------------------------------------------------

func _test_terrain() -> void:
	print("[Terrain]")
	var terrain := level.get_node_or_null("Terrain") as VillageTerrain
	_check(terrain != null and terrain.mesh != null, "village terrain mesh is built")
	if terrain == null:
		return
	var material := terrain.material_override as ShaderMaterial
	_check(material != null and material.shader.resource_path.ends_with("village_ground.gdshader"), "terrain uses the splat-blended ground shader")
	var flat := true
	for x in range(-43, 44, 3):
		for z in range(-43, 44, 3):
			flat = flat and is_zero_approx(terrain.height_at(x, z))
	_check(flat, "terrain is perfectly flat across the walkable village (|x|, |z| <= 43)")
	_check(terrain.height_at(66, 0) > 1.5 and terrain.height_at(0, -66) > 1.5 and terrain.height_at(-62, 62) > 1.5, "hills rise outside the boundary walls")
	var trees := terrain.get_node_or_null("HillTrees")
	var outside := trees != null and trees.get_children().all(func(t: Node3D) -> bool: return maxf(absf(t.position.x), absf(t.position.z)) > 44.0)
	_check(trees != null and trees.get_child_count() >= 50 and outside, "hill tree line stays outside the walls (%d trees)" % (trees.get_child_count() if trees else 0))
	var ground := level.get_node("Ground") as StaticBody3D
	_check(ground.get_node("CollisionShape3D") != null and level.has_node("Boundary/North"), "flat ground collision and boundary walls unchanged")
	var hidden := [level.get_node("Ground/Mesh"), level.get_node("ForestEntrance/ForestFloor"), level.get_node("ForestEntrance/Path"), level.get_node("ForestEntrance/ClearingGround")]
	for node in level.get_node("Paths").get_children():
		hidden.append(node)
	_check(hidden.all(func(n: Node3D) -> bool: return not n.visible), "old flat ground, path and forest planes are hidden (%d)" % hidden.size())


func _test_surfaces() -> void:
	print("[Painted surfaces]")
	_check(_splat(splat_a, Vector2(0, 3)).b > 0.9, "plaza is flagstone")
	_check(_splat(splat_a, Vector2(14, -1.5)).b > 0.9, "market square is flagstone")
	_check(_splat(splat_a, Vector2(-6.5, -6)).b > 0.9, "post office forecourt is flagstone")
	for name in (layout["cobble"] as Dictionary):
		var pts := _points(name)
		var mid := pts[pts.size() / 2]
		_check(_splat(splat_a, mid).g > 0.9 or _splat(splat_a, mid).b > 0.9, "%s road is cobbled" % name)
	for name in (layout["dirt"] as Dictionary):
		var pts := _points(name)
		var mid := (pts[0] + pts[1]) * 0.5
		_check(_splat(splat_a, mid).r > 0.9, "%s is a dirt lane" % name)
	for rect in layout["soil"]:
		_check(_splat(splat_a, Vector2((rect[0] + rect[2]) * 0.5, (rect[1] + rect[3]) * 0.5)).a > 0.9, "field at %s has tilled soil" % [rect])
	_check(_splat(splat_b, Vector2(14, -31)).r > 0.9 and _splat(splat_b, Vector2(0, 0)).r < 0.05, "forest floor blends in only around Whisperwood")
	_check(_splat(splat_b, Vector2(14, -34)).g > 0.9, "clearing has moss")
	var meadow := 0
	for x in range(-40, 41, 4):
		for z in range(-40, 41, 4):
			if _splat(splat_b, Vector2(x, z)).b > 0.3:
				meadow += 1
	_check(meadow > 10, "grass has dry/meadow variation patches (%d samples)" % meadow)


func _test_houses() -> void:
	print("[Houses face their lanes]")
	for name in FACING:
		var house := level.get_node("Buildings/" + name) as Node3D
		var door := house.global_basis.z
		var to_lane: Vector2 = FACING[name] - Vector2(house.global_position.x, house.global_position.z)
		var facing := Vector2(door.x, door.z).normalized().dot(to_lane.normalized())
		_check(facing > 0.6, "%s door faces its lane (%.2f)" % [name, facing])


func _test_roads_clear() -> void:
	print("[Roads clear]")
	var blocked: Array[String] = []
	var checked := 0
	for shape in level.find_children("*", "CollisionShape3D", true, false):
		var body := shape.get_parent()
		if not (body is StaticBody3D) or body.name in ["Ground", "Boundary"]:
			continue
		var path := str(level.get_path_to(body))
		if path.begins_with("Terrain/") or ROAD_EXCEPTIONS.any(func(e: String) -> bool: return path.begins_with(e)):
			continue
		var at := (shape as Node3D).global_position
		if maxf(absf(at.x), absf(at.z)) > 44.0:
			continue
		checked += 1
		var s := _splat(splat_a, Vector2(at.x, at.z))
		# Cobble core, or a lane core away from the plaza/market stones.
		if s.g > 0.6 or (s.r > 0.97 and s.b < 0.05 and _on_lane_core(Vector2(at.x, at.z))):
			blocked.append("%s (%.1f, %.1f)" % [path, at.x, at.z])
	_check(checked > 150 and blocked.is_empty(), "%d colliders keep roads and lanes clear %s" % [checked, blocked])


func _on_lane_core(at: Vector2) -> bool:
	for name in (layout["dirt"] as Dictionary):
		var pts := _points(name)
		var half: float = (layout["dirt_w"] as Dictionary).get(name, layout["lane_w"]) * 0.5 - 0.3
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(at, pts[i], pts[i + 1]).distance_to(at) < half:
				return true
	return false


func _test_spots_unchanged() -> void:
	print("[Gameplay positions]")
	for path in SPOTS:
		var node := level.get_node(path) as Node3D
		_check(Vector2(node.global_position.x, node.global_position.z).distance_to(SPOTS[path]) < 0.05, "%s unchanged" % path)
	_check(level.get_node("Buildings/AlchemyShop").global_position.is_equal_approx(Vector3(4, 0, 12)), "alchemy shop unchanged")
	_check(level.get_node("PostOffice").global_position.is_equal_approx(Vector3(-14, 0, -6)), "post office unchanged")


func _test_walks() -> void:
	print("[Walk every road and lane]")
	var names: Array = (layout["cobble"] as Dictionary).keys() + (layout["dirt"] as Dictionary).keys()
	for name in names:
		var pts := _points(name)
		if WALK_ENDS.has(name):
			pts[pts.size() - 1] = WALK_ENDS[name]
		player.teleport_to(Vector3(pts[0].x, 0, pts[0].y))
		await _frames(5)
		var ok := true
		for i in range(1, pts.size()):
			ok = ok and await _steer_to(Vector3(pts[i].x, 0, pts[i].y), 1.0, 900)
			if not ok:
				break
		_check(ok, "walk %s end to end (stopped at %s)" % [name, player.global_position.snapped(Vector3.ONE * 0.1)])
	# From the plaza centre to where each main road leaves it.
	for name in (layout["cobble"] as Dictionary):
		player.teleport_to(Vector3(0, 0, 1.5))
		await _frames(5)
		var start := _points(name)[0]
		_check(await _steer_to(Vector3(start.x, 0, start.y), 1.0, 900), "plaza connects to the %s road" % name)


func _steer_to(goal: Vector3, radius: float, max_frames: int) -> bool:
	var stuck := 0
	var last := player.global_position
	for i in max_frames:
		var to := goal - player.global_position
		to.y = 0
		if to.length() <= radius:
			break
		var right := player.camera_relative_direction(Vector2.RIGHT)
		var back := player.camera_relative_direction(Vector2.DOWN)
		var dir := to.normalized()
		_press(&"move_right", &"move_left", dir.dot(right))
		_press(&"move_back", &"move_forward", dir.dot(back))
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
