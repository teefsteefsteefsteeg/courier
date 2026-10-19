extends SceneTree
## Phase 8 milestone 8: Wyrmfall Vale, the new region south of Willowmere, in the real
## village with real keys.
## - The gate on the village's south edge: "[E] Travel to Wyrmfall Vale", the real E key
##   takes the courier to the vale's Arrival; the village is paused; the gate back
##   ("[E] Travel to Willowmere") returns the courier to the same village gate; a second
##   trip reuses the cached region.
## - The region: terrain collision everywhere the courier walks, the pool, river, plateau
##   stream (water_kit lake shader) and the waterfall (waterfall shader, mist); the map
##   texture and title; locations registered for `wyrmfall` and discovered by walking.
## - Walking with held movement keys: over the Old Stone Bridge; the river banks, the pool
##   rim, the cliff foot and the boundary hold the courier.
## - Tools: the axe, pickaxe and shovel at the region's sites, the rod at both banks.
## - A knockout in the vale returns the courier to its Arrival with full health.
##   godot --headless --path . --script res://tests/phase8_wyrmfall_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const L := preload("res://scripts/world/wyrmfall_layout.gd")

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var router: Node
var inventory: CourierInventory
var user: ToolUser
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_wyrmfall_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	router = get_first_node_in_group(&"phase6_router")
	inventory = CourierInventory.find(self)
	user = ToolUser.find_on(player)
	await _frames(20)
	for id in [&"woodcutter_axe", &"miner_pickaxe", &"garden_shovel", &"fishing_rod"]:
		inventory.add_item(inventory.get_definition(id))

	_test_layout()
	await _test_enter()
	await _test_region()
	await _test_walking()
	await _test_tools()
	await _test_knockout()
	await _test_return()

	print("\n=== Phase 8 Wyrmfall tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame


func _wait_region(region: StringName) -> void:
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == region and not router.get(&"crossing"):
			break
	await _frames(3)


func _vale() -> Node3D:
	return router.get(&"active_level") as Node3D


func _flat(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


## Height of the vale's terrain collider (not trees or props) under p.
func _ground(p: Vector2) -> float:
	var space := level.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.y), Vector3(p.x, -10.0, p.y), 1)
	for i in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return -INF
		if (hit["collider"] as Node).name == &"TerrainCollision":
			return (hit["position"] as Vector3).y
		query.exclude = query.exclude + [hit["rid"]]
	return -INF


func _place(p: Vector2) -> void:
	player.teleport_to(Vector3(p.x, _ground(p) + 0.3, p.y))
	await _physics(20)


## Holds the movement keys closest to a world direction (camera-relative, as a player
## would) for `seconds`.
func _walk(direction: Vector2, seconds: float) -> void:
	var basis := rig.camera.global_basis
	var forward := Vector2(-basis.z.x, -basis.z.z).normalized()
	var right := Vector2(basis.x.x, basis.x.z).normalized()
	var actions: Array[StringName] = []
	var f := direction.normalized().dot(forward)
	var r := direction.normalized().dot(right)
	if f > 0.35: actions.append(&"move_forward")
	if f < -0.35: actions.append(&"move_back")
	if r > 0.35: actions.append(&"move_right")
	if r < -0.35: actions.append(&"move_left")
	for action in actions:
		Input.action_press(action)
	await _physics(int(seconds * 60.0))
	for action in actions:
		Input.action_release(action)
	await _physics(5)


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame
	event = event.duplicate() as InputEventAction
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame


func _finish(max_frames: int = 900) -> void:
	var frames := 0
	while user.is_busy() and frames < max_frames:
		await physics_frame
		frames += 1


func _stand_at(target: ToolTarget, offset := Vector3(0.6, 0, 0.6)) -> void:
	player.teleport_to(target.get_reach_point() + offset + Vector3.UP * 0.3)
	for i in 30:
		await physics_frame
		if player.is_on_floor() and player.interaction.focused == target.interactable:
			break


# --- tests -------------------------------------------------------------------

func _test_layout() -> void:
	print("[Layout]")
	for p: Vector2 in [L.ARRIVAL, L.RETURN_GATE, L.CAMP_CENTRE, L.RUINS_CENTRE, L.CLIFF_END]:
		_check(not L.is_water(p) and L.height(p.x, p.y) > L.WATER_Y + 0.3 and L.plateau_factor(p.x, p.y) < 0.01, "%s is dry lowland" % p)
	_check(L.is_water(L.POOL_CENTRE) and L.is_water(L.RIVER[4]), "the pool and the river are water")
	_check(L.height(L.POOL_CENTRE.x, L.POOL_CENTRE.y) < L.WATER_Y - 1.0, "the pool is deep")
	_check(L.height(-6.0, -40.0) > L.PLATEAU_HEIGHT - 2.0 and L.height(10.0, -40.0) > L.PLATEAU_HEIGHT - 1.0, "the plateau stands above the cliff")
	var bridge := L.bridge_point()
	_check(L.river_distance(bridge) < 0.1 and L.polyline_distance(bridge, L.ROAD) < 0.1, "the bridge is where the road meets the river (%s)" % bridge)
	_check(absf(absf(L.bridge_direction().x) - absf(L.bridge_direction().y)) < 0.01, "the bridge runs along a keyboard diagonal")
	var gate := level.get_node_or_null("WyrmfallGate") as RegionGate
	_check(gate != null and gate.target_region == &"wyrmfall", "the village has a gate to Wyrmfall")


func _test_enter() -> void:
	print("[Enter through the village gate]")
	var gate := level.get_node("WyrmfallGate") as RegionGate
	player.teleport_to(gate.get_exit_point() + Vector3.UP * 0.2)
	for i in 40:
		await physics_frame
		if player.interaction.focused == gate.interactable:
			break
	_check(player.interaction.focused == gate.interactable, "standing by the gate focuses it")
	_check(gate.interactable.get_prompt_text_for(player) == "Travel to Wyrmfall Vale", "prompt: %s" % gate.interactable.get_prompt_text_for(player))
	var gold := CourierWallet.find(self).gold
	await _key(KEY_E)
	await _wait_region(&"wyrmfall")
	_check(router.get(&"region_id") == &"wyrmfall" and _vale() is WyrmfallVale, "the real E key enters Wyrmfall Vale")
	var arrival := _vale().get_node("Spawns/Arrival") as Marker3D
	_check(player.global_position.distance_to(arrival.global_position) < 1.0, "the courier stands at the Arrival")
	_check(not (level.get_node("PostOffice") as Node3D).visible, "the village is hidden while away")
	_check(ExplorationService.find(self).region_id == &"wyrmfall", "exploration follows the region")
	_check(CourierWallet.find(self).gold == gold and player.input_enabled, "nothing lost on the way; control returns")
	await _physics(10)
	_check(player.is_on_floor(), "the courier stands on the vale's ground")


func _test_region() -> void:
	print("[Region]")
	var vale := _vale()
	var probes := [L.ARRIVAL, L.CAMP_CENTRE, L.RUINS_CENTRE, L.CLIFF_END + Vector2(0, 3), Vector2(30, 5), Vector2(-20, 20)]
	var all_ground := true
	for p: Vector2 in probes:
		var y := _ground(p)
		if not is_finite(y) or absf(y - L.height(p.x, p.y)) > 0.6:
			all_ground = false
			printerr("    no matching ground at ", p, " ", y)
	_check(all_ground, "terrain collision under every landmark matches the layout")
	var lake := load("res://assets/vfx/water_kit/shaders/lake.gdshader")
	for name in ["Water/FallsPool", "Water/WyrmRiver", "Water/PlateauStream"]:
		var water := vale.get_node(name) as MeshInstance3D
		var material := water.material_override as ShaderMaterial
		_check(water.mesh != null and material != null and material.shader == lake, "%s uses the water kit lake shader" % name)
	var sheet := vale.get_node("Waterfall/Sheet") as MeshInstance3D
	_check((sheet.material_override as ShaderMaterial).shader.resource_path == "res://assets/shaders/waterfall.gdshader", "the waterfall uses the waterfall shader")
	var aabb := sheet.get_aabb()
	_check(aabb.size.y > L.PLATEAU_HEIGHT - 1.0 and aabb.position.y < L.WATER_Y + 0.2, "the falls drop from the plateau to the pool (%.1f m)" % aabb.size.y)
	_check((vale.get_node("Waterfall/Mist") as GPUParticles3D).emitting, "mist rises at the plunge")
	# Regression: the baked newmap textures were saved empty (keep_compressed_buffer off).
	var textures := 0
	var empty: Array[String] = []
	for model: MeshInstance3D in vale.find_children("Model", "MeshInstance3D", true, false):
		for surface in model.mesh.get_surface_count():
			var material := model.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null or material.albedo_texture == null:
				continue
			textures += 1
			var path := material.albedo_texture.resource_path
			if not path.begins_with("res://assets/generated/wyrmfall/") or material.albedo_texture.get_size() == Vector2.ZERO:
				empty.append(path)
	_check(textures > 20 and empty.is_empty(), "the newmap models' textures are baked and load (%d, bad: %s)" % [textures, empty])
	var controller := level.get_node("GameplayHUD/Minimap")
	_check(String(controller.expanded.map_texture.resource_path).ends_with("wyrmfall_map.png"), "the map shows Wyrmfall Vale")
	_check(controller.expanded_hint.text.begins_with("Wyrmfall Vale"), "the map's title")
	var exploration := ExplorationService.find(self)
	var ids: Array[StringName] = []
	for location in exploration.get_locations():
		ids.append(location.location_id)
	_check(ids.has(&"wyrmfall_falls") and ids.has(&"wyrmfall_bridge") and ids.has(&"wyrmfall_camp") and not ids.has(&"post_office"), "the vale's places are listed, the village's are not")
	await _place(L.CAMP_CENTRE + Vector2(0, -3))
	await _physics(30)
	_check(exploration.is_discovered(&"wyrmfall_camp"), "walking to the camp discovers it")


func _test_walking() -> void:
	print("[Walking]")
	var along := L.bridge_direction()
	var bridge := L.bridge_point()
	await _place(bridge - along * 7.0)
	await _walk(along, 3.2)
	var past := (_flat(player) - bridge).dot(along)
	_check(past > 4.5, "held keys carry the courier over the bridge (%.1f m past it)" % past)
	_check(player.global_position.y > L.WATER_Y + 0.2, "and not into the river")
	# Into the river from a bank.
	var bank_at := L.RIVER[5] as Vector2
	var dir := ((L.RIVER[6] as Vector2) - bank_at).normalized()
	var normal := Vector2(-dir.y, dir.x)
	await _place(bank_at + normal * (L.RIVER_HALF_WIDTH + 2.2))
	await _walk(-normal, 2.0)
	_check(L.river_distance(_flat(player)) > L.RIVER_HALF_WIDTH, "the river bank holds (%.2f m from the centreline)" % L.river_distance(_flat(player)))
	# Into the pool.
	await _place(L.POOL_CENTRE + Vector2(-0.7, 0.7).normalized() * (L.POOL_RADIUS + 2.0))
	await _walk(Vector2(0.7, -0.7), 2.0)
	_check(_flat(player).distance_to(L.POOL_CENTRE) > L.POOL_RADIUS, "the pool rim holds")
	# Up the cliff.
	await _place(Vector2(25.0, L.CLIFF_BASE_Z + 3.0))
	await _walk(Vector2(-0.7071, -0.7071), 2.0)
	_check(player.global_position.y < 3.0 and _flat(player).y > L.CLIFF_BASE_Z, "the cliff foot holds (y %.2f)" % player.global_position.y)
	# Out of the vale.
	await _place(Vector2(-40.0, 40.0))
	await _walk(Vector2(-0.7071, 0.7071), 3.0)
	_check(absf(_flat(player).x) < L.BOUNDARY and absf(_flat(player).y) < L.BOUNDARY, "the boundary holds")


func _test_tools() -> void:
	print("[Tools]")
	var sites := _vale().get_node("ToolSites")
	var ids := {}
	for child in sites.get_children():
		if child is ToolTarget:
			ids[(child as ToolTarget).target_id] = true
	_check(ids.size() == 5, "five tool sites with unique ids")
	for child in sites.get_children():
		for slime in _vale().get_node("Creatures").get_children():
			if _flat(child).distance_to(_flat(slime)) < 9.0:
				_check(false, "%s is clear of %s" % [child.name, slime.name])
	var tree := sites.get_node("WyrmfallTree1") as HarvestNode
	inventory.equip(&"woodcutter_axe")
	await _stand_at(tree)
	var wood := inventory.get_material_count(&"wood")
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"wood") > wood and not tree.is_available(), "the axe fells a Wyrmfall tree")
	var rock := sites.get_node("WyrmfallRock1") as HarvestNode
	inventory.equip(&"miner_pickaxe")
	await _stand_at(rock, Vector3(1.1, 0, 0.9))
	var stone := inventory.get_material_count(&"stone")
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"stone") > stone, "the pickaxe mines at the cliff foot")
	var soil := sites.get_node("WyrmfallSoil1") as HarvestNode
	inventory.equip(&"garden_shovel")
	await _stand_at(soil)
	var clay := inventory.get_material_count(&"clay")
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"clay") > clay, "the shovel digs by the camp")
	inventory.equip(&"fishing_rod")
	for spot_name in ["Water/RiverBank", "Water/PoolBank"]:
		var spot := _vale().get_node(spot_name) as FishingSpot
		await _stand_at(spot, Vector3(0, 0, 0.4))
		await _press(&"interact")
		_check(user.state == ToolUser.State.FISHING and user.fishing_pond == spot.pond, "%s: E casts the rod" % spot_name)
		_check(spot.pond.is_open_water(user.cast_point, 0.0), "%s: the bobber lands in open water" % spot_name)
		user.cancel()
		await _frames(3)
	_check(user.find_water(Vector3(L.CAMP_CENTRE.x, 1.0, L.CAMP_CENTRE.y)) == null, "the camp is not water")


func _test_knockout() -> void:
	print("[Knockout]")
	await _place(L.CAMP_CENTRE + Vector2(3, -3))
	var health := CombatHealth.find_on(player)
	health.apply_damage(health.get_max_health() + 10.0, Vector3.ZERO)
	for i in 240:
		await physics_frame
		if health.get_health() >= health.get_max_health() and not router.get(&"crossing") and player.input_enabled:
			break
	await _physics(5)
	var arrival := _vale().get_node("Spawns/Arrival") as Marker3D
	_check(router.get(&"region_id") == &"wyrmfall" and player.global_position.distance_to(arrival.global_position) < 1.5, "knocked out: back at the vale's Arrival")
	_check(health.get_health() >= health.get_max_health(), "with full health")


func _test_return() -> void:
	print("[Return]")
	var vale := _vale()
	var back := vale.get_node("ReturnGate") as RegionGate
	player.teleport_to(back.interactable.global_position + Vector3.UP * 0.2)
	for i in 40:
		await physics_frame
		if player.interaction.focused == back.interactable:
			break
	_check(back.interactable.get_prompt_text_for(player) == "Travel to Willowmere", "the gate back: %s" % back.interactable.get_prompt_text_for(player))
	await _key(KEY_E)
	await _wait_region(&"village")
	var gate := level.get_node("WyrmfallGate") as RegionGate
	_check(router.get(&"region_id") == &"village" and player.global_position.distance_to(gate.get_exit_point()) < 1.0, "the real E key returns the courier to the village gate")
	_check((level.get_node("PostOffice") as Node3D).visible and ExplorationService.find(self).region_id == &"village", "the village is back")
	await _physics(10)
	_check(player.is_on_floor(), "standing on the village ground")
	# Second trip: the region is kept as it was (the felled tree is still a stump).
	await _key(KEY_E)
	await _wait_region(&"wyrmfall")
	_check(_vale() == vale, "a second trip reuses the cached vale")
	_check(not (vale.get_node("ToolSites/WyrmfallTree1") as HarvestNode).is_available(), "the felled tree is still down")
	router.call(&"travel", &"village", &"", player)
	await _wait_region(&"village")
