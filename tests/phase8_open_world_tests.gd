extends SceneTree
## Phase 8 seamless open world (brief "true seamless open world"), in the real village:
## - Architecture: WorldStreamer with the Wyrmfall chunk set; only the always-loaded places
##   chunk is in the tree at the village; chunks near the courier load, far ones park.
## - No gate: no RegionGate or router region for Wyrmfall; the village's north wall is open at
##   the pass; terrain collision is continuous (no step, no hole) from the Whisperwood trail
##   into the vale.
## - MANDATORY: starting in Willowmere, the courier walks with held movement keys (8
##   keyboard directions, run held) through the Whisperwood, through the pass, down the vale
##   road and the falls path to the waterfall, then back the same way: never a teleport (no
##   frame moves more than 0.6 m), never a region change or router crossing, the same player
##   all the way, every chunk on the route active before the courier reaches it, the
##   courier never falls below the ground.
## - Systems carry across: HP/MP/rage, inventory, a buff, the quest state; tools work in the
##   vale (axe, pickaxe, shovel, rod), discovery and fog of war reach the vale, the one world
##   map shows it; a parked chunk keeps its state (a hurt slime, a felled tree).
## - The vale's content (from the old gated-region suite): terrain tiles match the layout,
##   water and waterfall shaders, baked newmap textures, the bridge carries held keys, the
##   river bank, pool rim, cliff foot, boundary and pass walls hold.
##   godot --headless --path . --script res://tests/phase8_open_world_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const L := preload("res://scripts/world/wyrmfall_layout.gd")
## Village plaza to the forest lane, the Whisperwood trail, the pass trail (world X/Z).
const VILLAGE_ROUTE := [Vector2(3.0, -3.0), Vector2(4.8, -5.2), Vector2(7.6, -9.6), Vector2(11.4, -15.6), Vector2(13.6, -18.6),
		Vector2(14.0, -24.0), Vector2(14.0, -28.6), Vector2(12.6, -36.0), Vector2(15.5, -45.0), Vector2(14.2, -53.0),
		Vector2(18.5, -62.0), Vector2(13.5, -71.0), Vector2(16.5, -80.0), Vector2(14.0, -90.0), Vector2(14.0, -98.6),
		Vector2(13.0, -104.0), Vector2(13.6, -111.0), Vector2(13.2, -117.5), Vector2(14.0, -124.0)]

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var streamer: WorldStreamer
var router: Node
var inventory: CourierInventory
var vitals: CourierVitals
var exploration: ExplorationService
## Largest single-frame movement seen while walking (teleport detector).
var max_step: float = 0.0
var lowest_y: float = INF
var crossings: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_open_world_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	streamer = WorldStreamer.find(self)
	router = get_first_node_in_group(&"phase6_router")
	inventory = CourierInventory.find(self)
	vitals = CourierVitals.find(self)
	exploration = ExplorationService.find(self)
	await _frames(20)

	await _test_architecture()
	await _test_no_gate_and_seam()
	await _test_walk_there_and_back()
	await _test_vale_content()
	await _test_systems_in_the_vale()
	await _test_parking_keeps_state()
	await _test_map()

	print("\n=== Phase 8 open world tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _flat(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


func _world(p: Vector2) -> Vector2:
	var w := L.to_world(p)
	return Vector2(w.x, w.z)


## The vale part of the route: the road from the pass, then the falls path (world X/Z).
func _vale_route() -> Array[Vector2]:
	var route: Array[Vector2] = []
	for i in 7:
		route.append(_world(L.ROAD[i]))
	for i in range(1, L.FALLS_PATH.size()):
		route.append(_world(L.FALLS_PATH[i]))
	return route


func _release_keys() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"run"]:
		Input.action_release(action)


## Holds the movement keys whose combined (camera-relative) direction is closest to the
## wanted world direction: the courier only ever gets the 8 keyboard directions.
func _hold_towards(direction: Vector2) -> void:
	var camera := get_root().get_camera_3d()
	var forward := Vector2(-camera.global_basis.z.x, -camera.global_basis.z.z).normalized()
	var right := Vector2(camera.global_basis.x.x, camera.global_basis.x.z).normalized()
	var best := []
	var best_dot := -INF
	for f: int in [-1, 0, 1]:
		for r: int in [-1, 0, 1]:
			if f == 0 and r == 0:
				continue
			var d := (forward * f + right * r).normalized()
			if d.dot(direction) > best_dot:
				best_dot = d.dot(direction)
				best = [f, r]
	for pair: Array in [[&"move_forward", best[0] == 1], [&"move_back", best[0] == -1], [&"move_right", best[1] == 1], [&"move_left", best[1] == -1]]:
		if pair[1]:
			Input.action_press(pair[0])
		else:
			Input.action_release(pair[0])


## Walks the route with held keys (running). Returns whether every waypoint was reached.
## Records the largest per-frame step, the lowest height and any router crossing.
func _walk(route: Array[Vector2], label: String) -> bool:
	var index := 0
	var last := player.global_position
	var stuck_time := 0.0
	var progress_at := player.global_position
	var sidestep := 0.0
	var side := 1.0
	var frames := 0
	Input.action_press(&"run")
	while index < route.size():
		var here := _flat(player)
		var target: Vector2 = route[index]
		if here.distance_to(target) < 1.3:
			index += 1
			continue
		var direction := (target - here).normalized()
		if sidestep > 0.0:
			direction = (direction + Vector2(-direction.y, direction.x) * side * 1.5).normalized()
			sidestep -= 1.0 / 60.0
		_hold_towards(direction)
		await physics_frame
		frames += 1
		var step := player.global_position.distance_to(last)
		max_step = maxf(max_step, step)
		lowest_y = minf(lowest_y, player.global_position.y)
		last = player.global_position
		if router != null and bool(router.get(&"crossing")):
			crossings += 1
		stuck_time += 1.0 / 60.0
		if stuck_time >= 1.0:
			if player.global_position.distance_to(progress_at) < 0.6:
				sidestep = 0.5
				side = -side
			progress_at = player.global_position
			stuck_time = 0.0
		if frames > 60 * 120:
			printerr("  walk %s stuck near %s (waypoint %d %s)" % [label, here, index, target])
			_release_keys()
			return false
	_release_keys()
	await _physics(10)
	return true


# --- tests ---------------------------------------------------------------------------

func _test_architecture() -> void:
	print("[Streaming architecture]")
	_check(streamer != null and streamer.entries.size() == 7, "the village holds the world streamer with the outlands and Wyrmfall's 6 chunks (%d)" % (streamer.entries.size() if streamer else 0))
	_check(streamer.is_active(&"outlands"), "the outlands (scenery round the playable areas) are always there")
	_check(streamer.is_active(&"wyrmfall_places"), "the always-loaded places chunk is in the tree")
	_check(not streamer.is_active(&"wyrmfall_0_0") and not streamer.is_active(&"wyrmfall_core"), "far chunks are not loaded at the village")
	var chunk := streamer.entries[&"wyrmfall_0_1"]["chunk"] as WorldChunk
	var expected := Rect2(L.WORLD_ORIGIN.x - L.HALF, L.WORLD_ORIGIN.z, 60.0, 60.0)
	_check(chunk.bounds.is_equal_approx(expected), "chunk bounds are world rectangles (%s)" % chunk.bounds)
	var places := streamer.get_chunk_node(&"wyrmfall_places")
	_check(places.global_position.is_equal_approx(L.WORLD_ORIGIN), "a chunk's root carries the vale's world origin")
	_check(exploration.get_location(&"wyrmfall_falls") != null and exploration.get_location(&"wyrmfall_falls").region_id == &"village", "the vale's places are overworld locations")


func _test_no_gate_and_seam() -> void:
	print("[No gate; a continuous seam]")
	var gates := level.find_children("*", "RegionGate", true, false).filter(func(g: Node) -> bool: return (g as RegionGate).target_region == &"wyrmfall")
	_check(gates.is_empty() and not (&"wyrmfall" in router.get(&"REGIONS")), "no gate and no router region lead to Wyrmfall")
	_check(is_zero_approx(L.height(-40.0, 60.0)) and L.height(-52.0, 59.0) > 4.0, "the pass comes down to the forest floor; the hills beside it stand")
	streamer.prepare_at(Vector3(14.0, 0.0, -124.0))
	await _physics(4)
	var space := level.get_world_3d().direct_space_state
	var previous := NAN
	var worst := 0.0
	var holes := 0
	for i in 41:
		var z := -104.0 - i
		# The ground itself: rays pass through props, statues and trees standing on it.
		var query := PhysicsRayQueryParameters3D.create(Vector3(14.0, 30.0, z), Vector3(14.0, -10.0, z), CombatController.WORLD_LAYER)
		var hit := space.intersect_ray(query)
		while not hit.is_empty() and not (String((hit["collider"] as Node).name) == "Ground" or String((hit["collider"] as Node).name).begins_with("TerrainCollision")):
			query.exclude = query.exclude + [(hit["collider"] as CollisionObject3D).get_rid()]
			hit = space.intersect_ray(query)
		if hit.is_empty():
			holes += 1
			continue
		var y: float = (hit["position"] as Vector3).y
		if not is_nan(previous):
			worst = maxf(worst, absf(y - previous))
		previous = y
	_check(holes == 0, "ground under every metre of the trail from the clearing into the vale (%d holes)" % holes)
	_check(worst < 0.45, "no step in the ground at the seam (largest rise between metres %.2f m)" % worst)
	var wall_hits := 0
	for x: float in [10.5, 14.0, 17.5]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1.0, -120.0), Vector3(x, 1.0, -130.0), CombatController.WORLD_LAYER))
		if not hit.is_empty() and (hit["position"] as Vector3).y < 5.0 and absf((hit["normal"] as Vector3).y) < 0.5:
			wall_hits += 1
	_check(wall_hits == 0, "no wall across the pass (%d)" % wall_hits)


func _test_walk_there_and_back() -> void:
	print("[MANDATORY: walk Willowmere -> Whisperwood -> Wyrmfall falls and back]")
	var player_id := player.get_instance_id()
	var hud_id := level.get_node("GameplayHUD").get_instance_id()
	player.teleport_to(Vector3(VILLAGE_ROUTE[0].x, 0.1, VILLAGE_ROUTE[0].y))
	await _physics(10)
	_check(not streamer.is_active(&"wyrmfall_0_1"), "starting in Willowmere: the vale's tiles are not loaded")
	var activated_at := {}
	var on_active := func(id: StringName) -> void: activated_at[id] = _flat(player)
	streamer.chunk_activated.connect(on_active)
	max_step = 0.0
	lowest_y = INF
	crossings = 0
	var route: Array[Vector2] = []
	route.assign(VILLAGE_ROUTE)
	route.append_array(_vale_route())
	var arrived := await _walk(route, "there")
	streamer.chunk_activated.disconnect(on_active)
	var falls := _world(L.POOL_CENTRE)
	_check(arrived and _flat(player).distance_to(falls) < 13.0, "the courier walked to the waterfall (%.1f m from the pool)" % _flat(player).distance_to(falls))
	_check(max_step < 0.6, "no teleport on the way (largest step %.2f m in one frame)" % max_step)
	_check(crossings == 0 and router.get(&"region_id") == &"village", "no region change or loading transition")
	_check(player.get_instance_id() == player_id and level.get_node("GameplayHUD").get_instance_id() == hud_id, "the same courier and HUD all the way")
	_check(lowest_y > -1.0 and player.is_on_floor(), "never below the ground (lowest %.2f m)" % lowest_y)
	var pass_entry := Vector2(14.0, -124.0)
	var early := true
	for id in [&"wyrmfall_0_1", &"wyrmfall_core"]:
		var at: Variant = activated_at.get(id)
		var chunk := streamer.entries[id]["chunk"] as WorldChunk
		early = early and at != null and chunk.distance_to(at) > 20.0
	_check(early, "the vale's chunks were loaded well before the courier reached them (%s)" % [activated_at])
	_check(streamer.is_active(&"wyrmfall_0_1") and streamer.is_active(&"wyrmfall_core"), "the tiles under the courier and the water are active")
	var waterfall := streamer.get_chunk_node(&"wyrmfall_core").get_node_or_null("Waterfall/Sheet") as MeshInstance3D
	_check(waterfall != null and waterfall.is_visible_in_tree(), "the waterfall is there")
	_check(exploration.is_discovered(&"wyrmfall_falls"), "reaching the falls discovers Wyrmfall")
	_check(exploration.is_explored(falls + Vector2(-4.0, 9.0)), "and reveals the vale on the map")
	print("  (streaming: %d activations, worst activation %.1f ms)" % [streamer.activations, streamer.max_activation_ms])
	# Back the same way.
	max_step = 0.0
	crossings = 0
	route.reverse()
	route.pop_front()
	var home := await _walk(route, "back")
	_check(home and _flat(player).distance_to(VILLAGE_ROUTE[0]) < 2.0, "and walked back to the plaza the same way")
	_check(max_step < 0.6 and crossings == 0 and router.get(&"region_id") == &"village", "no teleport or transition on the way back (%.2f m)" % max_step)
	await _frames(20)
	_check(not streamer.is_active(&"wyrmfall_0_0") and streamer.get_state(&"wyrmfall_0_1") == WorldStreamer.State.PARKED, "back home the vale's tiles are parked")


func _test_systems_in_the_vale() -> void:
	print("[Systems carry across]")
	CourierWallet.find(self).restore(500, 10)
	for id in [&"woodcutter_axe", &"miner_pickaxe", &"garden_shovel", &"fishing_rod"]:
		inventory.add_item(inventory.get_definition(id))
	inventory.add_material(inventory.get_material_definition(&"roast_ham"), 1)
	vitals.consume(&"roast_ham")
	vitals.spend(20.0)
	var mp := vitals.get_mana()
	var arrival := L.to_world(L.ARRIVAL, 0.0)
	streamer.prepare_at(arrival)
	player.teleport_to(arrival + Vector3.UP * 0.5)
	await _physics(20)
	_check(vitals.has_buff(&"hearty") and absf(vitals.get_mana() - mp) < 5.0 and CourierWallet.find(self).gold == 500, "buff, MP and gold are the same in the vale")
	var sites := streamer.get_chunk_node(&"wyrmfall_0_1").find_children("*", "ToolTarget", true, false) + streamer.get_chunk_node(&"wyrmfall_1_1").find_children("*", "ToolTarget", true, false)
	for cid in [&"wyrmfall_0_0", &"wyrmfall_1_0"]:
		streamer.prepare_at(streamer.get_chunk_node(&"wyrmfall_places").global_position)
		var node := streamer.get_chunk_node(cid)
		if node != null:
			sites += node.find_children("*", "ToolTarget", true, false)
	var ids := {}
	for site in sites:
		ids[(site as ToolTarget).target_id] = true
	_check(ids.has(&"wyrmfall_tree_1") and ids.has(&"wyrmfall_rock_1") and ids.has(&"wyrmfall_soil_1"), "the vale's tool sites stream in with their chunks (%s)" % [ids.keys()])
	# Fell a tree with the real interact key.
	var tree: HarvestNode = null
	for site in sites:
		if (site as ToolTarget).target_id == &"wyrmfall_tree_1":
			tree = site as HarvestNode
	_check(tree != null, "Wyrmfall tree 1 is in a loaded tile")
	if tree != null:
		inventory.equip(&"woodcutter_axe")
		var wood := inventory.get_material_count(&"wood")
		player.teleport_to(tree.get_reach_point() + Vector3(0.6, 0.3, 0.6))
		for i in 30:
			await physics_frame
			if player.is_on_floor() and player.interaction.focused == tree.interactable:
				break
		await _key(KEY_E)
		var user_busy := player.get_node("ToolUser") as ToolUser
		for i in 900:
			if not user_busy.is_busy():
				break
			await physics_frame
		_check(inventory.get_material_count(&"wood") > wood and not tree.is_available(), "the real E key with the axe fells a Wyrmfall tree (wood %d -> %d)" % [wood, inventory.get_material_count(&"wood")])
	# Fishing water in the core chunk.
	var user := player.get_node("ToolUser") as ToolUser
	var water_at := L.to_world(L.RIVER[4], 0.0)
	_check(user.find_water(water_at + Vector3.UP) != null, "the Wyrm River is fishing water")


func _test_parking_keeps_state() -> void:
	print("[Parked chunks keep their state]")
	var slimes := streamer.get_chunk_node(&"wyrmfall_1_1").find_children("*", "Enemy", true, false)
	_check(not slimes.is_empty(), "the vale's slimes live in its tiles")
	var slime := slimes[0] as Enemy
	slime.health.apply_damage(5.0)
	var hp := slime.health.get_health()
	var node := streamer.get_chunk_node(&"wyrmfall_1_1")
	player.teleport_to(Vector3(0.0, 0.1, 10.0))
	await _frames(30)
	_check(streamer.get_state(&"wyrmfall_1_1") == WorldStreamer.State.PARKED and not node.is_inside_tree(), "far away the tile is parked (out of the tree)")
	streamer.prepare_at(L.to_world(Vector2(30.0, 20.0)))
	_check(streamer.get_chunk_node(&"wyrmfall_1_1") == node and is_instance_valid(slime) and is_equal_approx(slime.health.get_health(), hp), "back, the same tile with the same hurt slime")
	var felled := false
	for site in streamer.get_chunk_node(&"wyrmfall_0_0").find_children("*", "HarvestNode", true, false) + streamer.get_chunk_node(&"wyrmfall_1_1").find_children("*", "HarvestNode", true, false):
		if (site as ToolTarget).target_id == &"wyrmfall_tree_1":
			felled = not (site as HarvestNode).is_available()
	_check(felled, "and the felled tree is still a stump")
	player.teleport_to(Vector3(3.0, 0.1, -3.0))
	await _frames(20)


func _test_map() -> void:
	print("[One world map]")
	var controller := level.get_node("GameplayHUD/Minimap")
	_check(controller.compact.map_world_rect == ExplorationService.WORLD_RECT and String(controller.compact.map_texture.resource_path).ends_with("world_map.png"), "the minimap shows the one world map over the whole world")
	_check(ExplorationService.WORLD_RECT.has_point(_world(L.POOL_CENTRE)) and ExplorationService.WORLD_RECT.has_point(Vector2(0, 0)), "the world rect covers Willowmere and Wyrmfall")
	streamer.prepare_at(L.to_world(L.FALLS_VIEW))
	player.teleport_to(L.to_world(L.FALLS_VIEW) + Vector3.UP * 0.5)
	await _physics(10)
	await _key(KEY_M)
	_check(controller.is_expanded() and controller.expanded.fixed_center.distance_to(_flat(player)) < 1.0, "M opens the world map on the courier's real position")
	var radius: float = controller.expanded.world_radius
	controller.zoom_map(1.25)
	_check(controller.expanded.world_radius > radius, "the map zooms out")
	Input.action_press(&"move_right")
	await _frames(20)
	Input.action_release(&"move_right")
	_check(controller.expanded.fixed_center.distance_to(_flat(player)) > 2.0, "and pans with the move keys")
	var ids := exploration.get_locations().map(func(l: WorldLocation) -> StringName: return l.location_id)
	_check(ids.has(&"wyrmfall_falls") and ids.has(&"post_office"), "Willowmere's and Wyrmfall's places are on the same map")
	await _key(KEY_M)
	_check(not controller.is_expanded(), "M closes it")
	player.teleport_to(Vector3(3.0, 0.1, -3.0))
	await _frames(10)


# --- the vale's content (ported from the gated-region suite) ------------------------------

## Height of the vale's terrain colliders (not trees or props) under a vale-space point.
func _ground(p: Vector2) -> float:
	var w := L.to_world(p)
	var space := level.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(w.x, 40.0, w.z), Vector3(w.x, -10.0, w.z), 1)
	for i in 10:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return -INF
		if String((hit["collider"] as Node).name).begins_with("TerrainCollision"):
			return (hit["position"] as Vector3).y
		query.exclude = query.exclude + [hit["rid"]]
	return -INF


## Puts the courier on the vale's ground at a vale-space point (chunks loaded first).
func _place(p: Vector2) -> void:
	var w := L.to_world(p)
	streamer.prepare_at(w)
	# A chunk just put back in the tree registers its colliders over the next frames.
	var y := -INF
	for i in 10:
		await _physics(1)
		y = _ground(p)
		if is_finite(y):
			break
	_check(is_finite(y), "the terrain at %s is there once its chunk is active" % p) if not is_finite(y) else null
	player.teleport_to(Vector3(w.x, (y if is_finite(y) else L.height(p.x, p.y)) + 0.3, w.z))
	await _physics(20)


## Holds the movement keys closest to a world direction for `seconds`.
func _hold(direction: Vector2, seconds: float) -> void:
	_hold_towards(direction.normalized())
	await _physics(int(seconds * 60.0))
	_release_keys()
	await _physics(5)


func _test_vale_content() -> void:
	print("[The vale's content]")
	# Stand in the vale: chunks prepared for a point the courier is not at are parked again
	# by the next streaming scan.
	await _place(Vector2.ZERO)
	var all_ground := true
	for p: Vector2 in [L.ARRIVAL, L.CAMP_CENTRE, L.RUINS_CENTRE, L.CLIFF_END + Vector2(0, 3), Vector2(30, 5), Vector2(-20, 20), L.FALLS_VIEW]:
		var y := _ground(p)
		if not is_finite(y) or absf(y - L.height(p.x, p.y)) > 0.6:
			all_ground = false
			printerr("    no matching ground at ", p, " ", y)
	_check(all_ground, "terrain tiles under every landmark match the layout")
	var core := streamer.get_chunk_node(&"wyrmfall_core")
	var lake := load("res://assets/vfx/water_kit/shaders/lake.gdshader")
	for water_name in ["Water/FallsPool", "Water/WyrmRiver", "Water/PlateauStream"]:
		var water := core.get_node(water_name) as MeshInstance3D
		var material := water.material_override as ShaderMaterial
		_check(water.mesh != null and material != null and material.shader == lake, "%s uses the water kit lake shader" % water_name)
	var sheet := core.get_node("Waterfall/Sheet") as MeshInstance3D
	_check((sheet.material_override as ShaderMaterial).shader.resource_path == "res://assets/shaders/waterfall.gdshader", "the waterfall uses the waterfall shader")
	var aabb := sheet.get_aabb()
	_check(aabb.size.y > L.PLATEAU_HEIGHT - 1.0 and aabb.position.y < L.WATER_Y + 0.2, "the falls drop from the plateau to the pool (%.1f m)" % aabb.size.y)
	_check((core.get_node("Waterfall/Mist") as GPUParticles3D).emitting, "mist rises at the plunge")
	var textures := 0
	var empty: Array[String] = []
	for id in streamer.get_active_ids():
		for model: MeshInstance3D in streamer.get_chunk_node(id).find_children("Model", "MeshInstance3D", true, false):
			for surface in model.mesh.get_surface_count():
				var material := model.mesh.surface_get_material(surface) as BaseMaterial3D
				if material == null or material.albedo_texture == null:
					continue
				textures += 1
				if material.albedo_texture.get_size() == Vector2.ZERO:
					empty.append(material.albedo_texture.resource_path)
	_check(textures > 20 and empty.is_empty(), "the newmap models' textures are baked and load (%d, bad: %s)" % [textures, empty])
	# Walking over the bridge and against the walls.
	var along := L.bridge_direction()
	var bridge := L.bridge_point()
	await _place(bridge - along * 7.0)
	await _hold(Vector2(along.x, along.y), 3.2)
	var past := (L.to_local(player.global_position) - bridge).dot(along)
	_check(past > 4.5 and player.global_position.y > L.WATER_Y + 0.2, "held keys carry the courier over the Old Stone Bridge (%.1f m past it)" % past)
	var bank_at := L.RIVER[5] as Vector2
	var dir := ((L.RIVER[6] as Vector2) - bank_at).normalized()
	var normal := Vector2(-dir.y, dir.x)
	await _place(bank_at + normal * (L.RIVER_HALF_WIDTH + 2.2))
	await _hold(-normal, 2.0)
	_check(L.river_distance(L.to_local(player.global_position)) > L.RIVER_HALF_WIDTH, "the river bank holds")
	await _place(L.POOL_CENTRE + Vector2(-0.7, 0.7).normalized() * (L.POOL_RADIUS + 2.0))
	await _hold(Vector2(0.7, -0.7), 2.0)
	_check(L.to_local(player.global_position).distance_to(L.POOL_CENTRE) > L.POOL_RADIUS, "the pool rim holds")
	await _place(Vector2(25.0, L.CLIFF_BASE_Z + 3.0))
	await _hold(Vector2(-0.7071, -0.7071), 2.0)
	_check(player.global_position.y < 3.0 and L.to_local(player.global_position).y > L.CLIFF_BASE_Z, "the cliff foot holds (y %.2f)" % player.global_position.y)
	await _place(Vector2(-46.0, 20.0))
	await _hold(Vector2(-1.0, 0.0), 3.0)
	_check(L.to_local(player.global_position).x > -L.BOUNDARY, "the vale's west boundary holds")
	await _place(Vector2(-40.0, 57.0))
	await _hold(Vector2(-1.0, 0.0), 2.0)
	_check(L.to_local(player.global_position).x > -40.0 - L.PASS_OPEN - 0.1, "the pass walls hold")
	player.teleport_to(Vector3(3.0, 0.1, -3.0))
	await _physics(20)
