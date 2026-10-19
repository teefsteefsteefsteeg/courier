extends SceneTree
## Phase 7, Milestone A: the Courier Guild board, the removed cargo exhibit, NPCs turning to
## the courier, the widened roads and the relocated, denser Whisperwood.
##   godot --headless --path . --script res://tests/phase7_village_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const BOARD_PATH := "PostOffice/Markers/QuestBoardSpot/QuestBoard"
## The forest gate, the Moonstone Clearing and the annex the Whisperwood fills.
const FOREST_GATE := Vector3(14, 0, -90)
const CLEARING := Vector2(14, -104)
const ANNEX := Rect2(-20, -124, 64, 80)

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var layout: Dictionary


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase7_village_tests.json"
	root.add_child(level)
	player = level.get_node("Player")
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/terrain/village_layout.json"))
	await _frames(20)

	_test_board()
	await _test_board_presentation()
	_test_exhibit_removed()
	await _test_npc_attention()
	await _test_shopkeepers_face_counter()
	_test_forest_layout()
	_test_forest_atmosphere()
	_test_trail_clear()
	await _test_forest_ground()
	_test_world_rect()
	_test_egg_budget()

	print("\n=== Phase 7 village tests: %d passed, %d failed ===" % [_passes, _failures])
	if FileAccess.file_exists("user://phase7_village_tests.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://phase7_village_tests.json"))
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
		await process_frame


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _polyline_distance(p: Vector2, points: Array) -> float:
	var best := INF
	for i in points.size() - 1:
		var a := Vector2(points[i][0], points[i][1])
		var b := Vector2(points[i + 1][0], points[i + 1][1])
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


func _shape_radius(shape_node: CollisionShape3D) -> float:
	var scale := shape_node.global_basis.get_scale()
	var shape := shape_node.shape
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius * scale.x
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius * scale.x
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius * scale.x
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size * scale
		return minf(size.x, size.z) * 0.5
	return 0.3


# --- tests -------------------------------------------------------------------

func _test_board() -> void:
	print("[Courier Guild board]")
	var board := level.get_node(BOARD_PATH) as Node3D
	var model := board.get_node_or_null("Model")
	_check(model != null and model.scene_file_path == "res://assets/generated/phase7/courier_guild_board.glb", "board uses the Blender guild board model")
	var meshes := board.find_children("*", "MeshInstance3D", true, false)
	var tris := 0
	for mesh_node in meshes:
		var mesh := (mesh_node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			tris += mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3
	_check(tris > 1500, "board model is detailed (%d triangles)" % tris)
	_check(board.find_children("*", "Label3D", true, false).is_empty() and board.find_children("*", "OmniLight3D", true, false).is_empty(), "board has no floating labels or glow lights")
	_check(board.find_children("*", "Interactable", true, false).size() == 1, "board has exactly one interaction point")
	# On the plaza by the post-office gate, its notices facing the isometric camera (south-east).
	var at := _flat(board.global_position)
	_check(at.distance_to(Vector2(-3, -4)) < 0.5, "board stands on the plaza by the post office (%s)" % at)
	# The board's notices and interaction point are on its local +Z side.
	var front := board.global_basis.z
	_check(Vector2(front.x, front.z).normalized().dot(Vector2(0.7071, 0.7071)) > 0.95, "board front faces the camera")
	var space := level.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.6
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, board.global_position + board.global_basis.z * 1.6 + Vector3.UP)
	query.exclude = [player.get_rid()]
	_check(space.intersect_shape(query).is_empty(), "the ground in front of the board is clear")


func _test_board_presentation() -> void:
	print("[Board presentation]")
	var board := level.get_node(BOARD_PATH) as Node3D
	player.teleport_to(board.global_position + board.global_basis.z * 1.5)
	await _frames(30)
	# The guild board had a cyan route beam and a second floating name over it; the prompt
	# is now the only thing that names it.
	var near: Array[String] = []
	for node in level.find_children("*", "", true, false):
		if not (node is Label3D or node is GPUParticles3D or node is OmniLight3D):
			continue
		var visual := node as Node3D
		# Street lamps light the plaza; they are not markers.
		if not visual.is_visible_in_tree() or board.is_ancestor_of(visual) or player.is_ancestor_of(visual) or String(level.get_path_to(visual)).begins_with("Props/Lamp"):
			continue
		if _flat(visual.global_position).distance_to(_flat(board.global_position)) < 2.5:
			near.append(String(level.get_path_to(visual)))
	_check(near.is_empty(), "no beam, glow or floating label over the board %s" % [near])
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	await _frames(5)
	_check(prompt.panel.visible and prompt._focused != null and prompt._focused.get_parent() == board, "standing at the board shows one prompt for it")


func _test_exhibit_removed() -> void:
	print("[Cargo exhibit]")
	_check(not level.has_node("PostOffice/Phase3Showcase") and level.find_children("Phase3Showcase", "", true, false).is_empty(), "the Dragon Egg / potion exhibit is gone from the village")
	_check(ResourceLoader.exists("res://scenes/gameplay/phase3_visual/phase3_showcase.tscn") and ResourceLoader.exists("res://data/packages/pkg_dragon_egg.tres"), "its source scene and package data are kept")
	_check(level.has_node("PostOffice/Markers/ParcelPickupSpot/DragonEggPickup"), "the real Dragon Egg pickup is still there")


func _test_npc_attention() -> void:
	print("[NPCs face the courier]")
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	var home := bram.get_home_yaw()
	# Stand off to Bram's side so the turn is large.
	var side := bram.global_position + bram.global_basis.x * 2.0
	player.teleport_to(side)
	await _frames(30)
	_check(is_equal_approx(bram.visual.rotation.y, home), "Bram ignores a courier who only walks by")
	bram.interactable.interact(player)
	await create_timer(1.2).timeout  # turns run on real time
	var to_player := player.global_position - bram.global_position
	var wanted := FacingComponent.yaw_for_direction(to_player) - bram.global_rotation.y
	_check(absf(angle_difference(bram.visual.rotation.y, wanted)) < 0.1, "Bram turns to the courier he talks to (%.2f, want %.2f, home %.2f)" % [bram.visual.rotation.y, wanted, home])
	_check(is_zero_approx(bram.visual.rotation.x) and is_zero_approx(bram.visual.rotation.z), "the turn is about the Y axis only")
	# The turn is smooth: halfway through it is between the two facings.
	var dialogue := level.get_node("DialogueBox") as DialogueBox
	if dialogue.has_method(&"close"):
		dialogue.call(&"close")
	player.teleport_to(bram.global_position + side - bram.global_position + bram.global_basis.x * 6.0)
	await _frames(3)
	var mid := bram.visual.rotation.y
	_check(absf(angle_difference(mid, home)) > 0.05 and absf(angle_difference(mid, wanted)) > 0.05, "turning back is smooth, not a snap")
	await create_timer(1.5).timeout
	_check(not bram.is_attending() and absf(angle_difference(bram.visual.rotation.y, home)) < 0.05, "Bram returns to his post when the courier leaves")


func _test_shopkeepers_face_counter() -> void:
	print("[Shopkeepers]")
	for path in ["Armory/Merchant", "ToolSites/ToolStall/Merchant"]:
		var merchant := level.get_node(path) as NPC
		var shop := merchant.get_parent() as Node3D
		var front := shop.call(&"get_shop_front") as Marker3D
		# NPCs look along their visual's local -Z.
		var facing := -merchant.visual.global_basis.z
		var to_front := front.global_position - merchant.global_position
		_check(Vector2(facing.x, facing.z).normalized().dot(Vector2(to_front.x, to_front.z).normalized()) > 0.7, "%s faces the customers across the counter" % merchant.npc_name)
		_check(_flat(merchant.interactable.global_position).distance_to(_flat(front.global_position)) < _flat(merchant.global_position).distance_to(_flat(front.global_position)), "%s serves on the customer side" % merchant.npc_name)
	var brenna := level.get_node("Armory/Merchant") as NPC
	var shop_front := (level.get_node("Armory") as Armory).get_shop_front()
	player.teleport_to(shop_front.global_position + Vector3(1.2, 0, 0))
	await _frames(10)
	brenna.interactable.interact(player)
	await create_timer(1.2).timeout
	var to_player := player.global_position - brenna.global_position
	var wanted := FacingComponent.yaw_for_direction(to_player) - brenna.global_rotation.y
	_check(absf(angle_difference(brenna.visual.rotation.y, wanted)) < 0.1, "Brenna turns to the courier while trading")
	var shop_ui := level.find_children("*", "ShopUI", true, false)
	if not shop_ui.is_empty() and (shop_ui[0] as ShopUI).is_open():
		(shop_ui[0] as ShopUI).close()
	await _frames(5)


func _test_forest_layout() -> void:
	print("[Whisperwood]")
	var forest := level.get_node("ForestEntrance") as Node3D
	_check(forest.global_position.is_equal_approx(FOREST_GATE), "the forest gate moved 70 m north (%s)" % forest.global_position)
	var wood := level.get_node_or_null("WhisperwoodForest") as Node3D
	_check(wood != null, "the generated Whisperwood is in the village")
	if wood == null:
		return
	var trees := wood.get_node("Trees").get_children()
	var models := {}
	for tree in trees:
		var tree_name := String(tree.name)
		models[tree_name.substr(tree_name.find("_") + 1)] = true
	_check(trees.size() >= 150, "the wood is dense (%d trees)" % trees.size())
	_check(models.size() >= 12, "and varied (%d tree models)" % models.size())
	_check(trees.all(func(t: Node) -> bool: return t.has_node("CameraOccluder") and t.has_node("Trunk")), "every forest tree has a trunk collider and fades for the camera")
	var undergrowth := 0
	for field in wood.get_node("Undergrowth").get_children():
		undergrowth += (field.get(&"transforms") as Array).size()
	_check(undergrowth >= 1200, "bushes, ferns, grass and flowers (%d)" % undergrowth)
	var props := wood.get_node("Props").get_children()
	var kinds := {}
	for prop in props:
		kinds[String(prop.name).rstrip("0123456789")] = true
	_check(kinds.has("Rock") and kinds.has("Log") and kinds.has("Mushrooms") and kinds.has("Glow"), "rocks, fallen logs and mushrooms (%s)" % [kinds.keys()])
	_check(wood.has_node("EdgeGate") and wood.has_node("EdgeSign"), "a gate and signpost mark where the trail enters the wood")
	# Denser in the wood than in the outskirts it thins out over.
	var inside := 0
	var outskirts := 0
	for tree in trees:
		var z := (tree as Node3D).global_position.z
		if z < -60.0:
			inside += 1
		elif z > -53.0:
			outskirts += 1
	_check(inside > outskirts * 6, "the treeline thins out towards the village (%d inside, %d outskirts)" % [inside, outskirts])


func _test_forest_atmosphere() -> void:
	var wood := level.get_node("WhisperwoodForest")
	var fog := wood.find_children("*", "FogVolume", true, false)
	_check(not fog.is_empty() and ANNEX.encloses(Rect2(_flat((fog[0] as FogVolume).global_position) - Vector2(1, 1), Vector2(2, 2))), "mist hangs over the wood only")
	_check(wood.find_children("*", "GPUParticles3D", true, false).size() >= 3, "fireflies drift over the glades and the clearing")


## Nothing solid stands on the trail, the glade and hollow paths, or in the clearing.
func _test_trail_clear() -> void:
	print("[Paths through the wood]")
	var lanes := ["whisperwood_trail", "glade_path", "hollow_path"]
	var blocked: Array[String] = []
	for node in level.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		var body := shape_node.get_parent()
		if not (body is StaticBody3D) or body.name == "Ground" or String(level.get_path_to(body)).begins_with("Boundary"):
			continue
		var path := String(level.get_path_to(body))
		if path.begins_with("ForestEntrance/Gate") or path.begins_with("WhisperwoodForest/EdgeGate") or path.begins_with("NPCs/"):
			continue
		var at := _flat(shape_node.global_position)
		if not ANNEX.has_point(at) or shape_node.global_position.y < -2.0:
			continue
		var radius := _shape_radius(shape_node)
		for lane in lanes:
			var half: float = (layout["dirt_w"] as Dictionary)[lane] * 0.5 - 0.3
			if _polyline_distance(at, layout["dirt"][lane]) - radius < half:
				blocked.append("%s on %s" % [path, lane])
	_check(blocked.is_empty(), "the forest paths are clear %s" % [blocked])


func _test_forest_ground() -> void:
	print("[Walking in the wood]")
	# Regression: the ground collider ended at z = -60 and the courier fell through the forest.
	player.teleport_to(Vector3(CLEARING.x, 0, CLEARING.y + 3))
	for i in 60:
		await physics_frame
	_check(absf(player.global_position.y) < 0.2 and player.is_on_floor(), "the courier stands on the clearing (y=%.2f)" % player.global_position.y)


func _test_world_rect() -> void:
	print("[Map]")
	var rect := ExplorationService.WORLD_RECT
	_check(rect.encloses(ANNEX) and rect.has_point(CLEARING), "the exploration map covers the Whisperwood")
	var map := load("res://assets/textures/map/world_map.png") as Texture2D
	_check(map != null and is_equal_approx(float(map.get_width()) / map.get_height(), rect.size.x / rect.size.y), "the baked map matches the world rect (%s)" % (map.get_size() if map else Vector2.ZERO))
	var edge := level.get_node("ForestEntrance/Locations/WhisperwoodEdge") as Node3D
	_check(_flat(edge.global_position).distance_to(Vector2(14, -54)) < 0.5, "Whisperwood Edge is discovered at the edge gate")


## The Dragon Egg stays in its safe band for the walk from the post office to Elowen.
func _test_egg_budget() -> void:
	print("[Dragon Egg]")
	var egg := load("res://data/packages/pkg_dragon_egg.tres") as PackageDefinition
	var safe_seconds := (egg.starting_temperature - egg.ideal_temperature_min) / egg.temperature_change_rate
	var route: Array = [[-11, -8], [-3, -6], [4.8, -5.2], [11.4, -15.6], [14, -28.6]] + (layout["dirt"]["whisperwood_trail"] as Array).slice(1)
	var length := 0.0
	for i in route.size() - 1:
		length += Vector2(route[i][0], route[i][1]).distance_to(Vector2(route[i + 1][0], route[i + 1][1]))
	var walk := (player.get_node("MovementComponent") as MovementComponent).walk_speed if player.has_node("MovementComponent") else 5.0
	_check(length / walk < safe_seconds * 0.6, "walking the %.0f m route takes %.0f s of the egg's %.0f safe seconds" % [length, length / walk, safe_seconds])
