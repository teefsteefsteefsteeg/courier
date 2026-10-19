extends SceneTree
## Phase 5H village checks: the Armory crate no longer blocks Weaponsmith Brenna, the houses
## that were cramped together have room (measured collider gaps), the courier can walk around
## every moved building and up to each door, nothing solid or scattered stands inside a moved
## house, gameplay spots, NPCs and portals stay clear, and the baked world map shows the new
## layout. Also checks the Phase 5H movement speeds and their animation playback rates.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5h_village_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const WORLD_MAP := "res://assets/textures/map/world_map.png"
## Buildings moved by the spacing pass: node -> [old XZ, new XZ, door (lane end) XZ].
const MOVED := {
	"Buildings/CottageBlue": [Vector2(-4, -17), Vector2(-8.6, -20.2), Vector2(-8.6, -17.2)],
	"Buildings/CottageOak": [Vector2(-17, 10), Vector2(-19.6, 10.6), Vector2(-19.6, 7.8)],
	"Buildings/CottageFern": [Vector2(18, 13), Vector2(19.8, 14.2), Vector2(19.8, 11.2)],
	"VillageDressing/Landmarks/BellTower": [Vector2(0, -12), Vector2(-1.4, -10.4), Vector2.INF],
}
## Every building of the village proper, for the spacing checks.
const BUILDINGS := ["Buildings/AlchemyShop", "Buildings/CottageRose", "Buildings/CottageOak", "Buildings/CottageFern",
	"Buildings/CottageBlue", "Buildings/CottageMill", "Buildings/CottageHill", "Buildings/CottageWillow",
	"Buildings/CottageBrook", "Buildings/CottageMoss", "Armory/Hall", "VillageDressing/Landmarks/BellTower", "PostOffice/Building"]
## Pairs that were cramped before Phase 5H (gap in m then) and the minimum gap now.
const WIDENED := [
	["Buildings/CottageBlue", "VillageDressing/Landmarks/BellTower", 1.1, 6.0],
	["Armory/Hall", "VillageDressing/Landmarks/BellTower", 1.2, 3.0],
	["Buildings/CottageBlue", "PostOffice/Building", 3.9, 6.0],
	["Buildings/CottageBlue", "Armory/Hall", 4.3, 7.0],
	["Buildings/CottageRose", "Buildings/CottageOak", 5.5, 7.5],
]
## Narrowest gap allowed anywhere: the alley between the blacksmith and the post office
## (2.9 m, unchanged: moving the blacksmith west would put it on the farm track).
const MIN_GAP := 2.8
## Colliders whose centre is deeper than this are below the surface the courier walks on.
const SURFACE_DEPTH := -3.0
## Scattered dressing allowed against a house wall (flower beds, vines).
const WALL_DRESSING := ["VillageDressing/Homes/", "MegaKitPilotDressing/Houses/"]

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var armory: Armory


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	armory = level.get_node("Armory") as Armory
	for i in 10:
		await physics_frame

	_test_armory_layout()
	await _test_armory_approach()
	_test_spacing()
	_test_moved_buildings_clear()
	_test_spots_clear()
	_test_world_map()
	await _test_walk_around()
	_test_movement_speeds()
	await _test_movement_feel()

	print("\n=== Phase 5H village tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _xz(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


# --- Task 1: the Armory crate ----------------------------------------------------------

func _test_armory_layout() -> void:
	print("[Armory: the barrel no longer blocks Brenna]")
	var barrel := armory.get_node_or_null(^"Displays/WeaponBarrel") as StaticBody3D
	_check(barrel != null and barrel.find_children("*", "CollisionShape3D", true, false).size() == 1, "the weapon barrel is still there as solid decoration")
	if barrel == null:
		return
	var front := _xz(armory.get_shop_front())
	var merchant := _xz(armory.merchant)
	_check(_xz(barrel).distance_to(front) > 3.0, "barrel is %.1f m from the shop front (was 0.6 m)" % _xz(barrel).distance_to(front))
	_check(_xz(barrel).distance_to(merchant) < 5.0, "barrel stays beside the shop (%.1f m from Brenna)" % _xz(barrel).distance_to(merchant))
	# The yard in front of the counter, from the counter to the forest road, is free.
	var corridor := Rect2(front.x - 1.0, front.y - 0.4, 2.0, 5.0)
	var blocking: Array[String] = []
	for shape in level.find_children("*", "CollisionShape3D", true, false):
		var body := shape.get_parent()
		if body is PhysicsBody3D and not body.name in ["Ground", "Boundary"] and body != player and _at_surface(shape) and _footprint(shape).intersects(corridor):
			blocking.append(str(level.get_path_to(body)))
	_check(blocking.is_empty(), "the walk-up corridor to the counter is clear %s" % [blocking])


func _test_armory_approach() -> void:
	print("[Armory: walking up to Brenna]")
	var detector := player.get_node(^"InteractionDetector") as InteractionDetector
	var front := armory.get_shop_front().global_position
	var routes := {
		"plaza": [Vector3(0, 0, 1.5), Vector3(3.6, 0, -6.0), Vector3(5.9, 0, -10.0)],
		"forest road": [Vector3(11.4, 0, -15.6), Vector3(8.6, 0, -11.4)],
		"bell tower": [Vector3(-1.4, 0, -7.6), Vector3(2.0, 0, -12.0)],
	}
	for route in routes:
		var points: Array = routes[route]
		player.teleport_to(points[0])
		await _frames(5)
		var ok := true
		for i in range(1, points.size()):
			ok = ok and await _steer_to(points[i], 0.8, 900)
		# Stop as soon as the counter is within reach, like a player would.
		ok = ok and await _steer_until(front, func() -> bool: return detector.focused == armory.merchant.interactable, 600)
		var gap := Vector2(player.global_position.x - front.x, player.global_position.z - front.z).length()
		_check(ok, "from the %s, Brenna comes within reach before the counter (%.1f m short of the shop front)" % [route, gap])
	player.teleport_to(front + Vector3(0, 0, 1.2))
	await _frames(5)
	_check(detector.focused == armory.merchant.interactable, "Brenna can be reached from the yard, 1.2 m in front of the shop front")
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	await process_frame
	await process_frame
	_check(prompt.label.text.ends_with("Browse wares of Weaponsmith Brenna"), "prompt offers Brenna's wares (%s)" % prompt.label.text)
	player.interaction.try_interact(player)
	await _frames(3)
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	_check(shop.is_open(), "talking to Brenna opens the Armory shop")
	shop.close()
	await _frames(3)


# --- Task 2: spacing ---------------------------------------------------------------------

func _test_spacing() -> void:
	print("[Village spacing]")
	for path in MOVED:
		var spec: Array = MOVED[path]
		var node := level.get_node(path) as Node3D
		_check(_xz(node).distance_to(spec[1]) < 0.01, "%s moved from %s to %s" % [path.get_file(), spec[0], spec[1]])
	for pair in WIDENED:
		var gap := _gap(pair[0], pair[1])
		_check(gap >= pair[3], "%s and %s are %.1f m apart (were %.1f m, need %.1f m)" % [pair[0].get_file(), pair[1].get_file(), gap, pair[2], pair[3]])
	var narrowest := INF
	var narrow_pair := ""
	for i in BUILDINGS.size():
		for j in range(i + 1, BUILDINGS.size()):
			var gap := _gap(BUILDINGS[i], BUILDINGS[j])
			if gap < narrowest:
				narrowest = gap
				narrow_pair = "%s/%s" % [BUILDINGS[i].get_file(), BUILDINGS[j].get_file()]
	_check(narrowest >= MIN_GAP, "every pair of village buildings is at least %.1f m apart (narrowest %.1f m: %s)" % [MIN_GAP, narrowest, narrow_pair])
	# Inside the walls and off the forest floor.
	for path in MOVED:
		var rect := _building_rect(path)
		_check(Rect2(-43, -43, 86, 86).encloses(rect), "%s stays inside the playable village" % path.get_file())


func _test_moved_buildings_clear() -> void:
	print("[Moved buildings stand clear]")
	for path in MOVED:
		var building := level.get_node(path) as Node3D
		var rect := _building_rect(path)
		var solids: Array[String] = []
		for shape in level.find_children("*", "CollisionShape3D", true, false):
			var body := shape.get_parent()
			if not body is PhysicsBody3D or body.name in ["Ground", "Boundary"] or body == player or building.is_ancestor_of(shape) or not _at_surface(shape):
				continue
			if _footprint(shape).intersects(rect.grow(-0.05)):
				solids.append(str(level.get_path_to(body)))
		_check(solids.is_empty(), "no solid overlaps %s %s" % [path.get_file(), solids])
		var scattered: Array[String] = []
		for field in level.find_children("*", "ScatterField", true, false):
			var field_path := str(level.get_path_to(field))
			if WALL_DRESSING.any(func(prefix: String) -> bool: return field_path.begins_with(prefix)):
				continue
			var inside := 0
			for xform in (field as ScatterField).transforms:
				var at := (field as Node3D).global_transform * xform.origin
				if rect.has_point(Vector2(at.x, at.z)):
					inside += 1
			if inside > 0:
				scattered.append("%s x%d" % [field_path, inside])
		_check(scattered.is_empty(), "no grass, flowers or trees inside %s %s" % [path.get_file(), scattered])


func _test_spots_clear() -> void:
	print("[Gameplay spots, NPCs and portals]")
	# The post office is an open hall: Bram and the spawn point are inside it by design.
	var rects: Array[Rect2] = []
	for path in BUILDINGS:
		if path != "PostOffice/Building":
			rects.append(_building_rect(path))
	var spots: Array[Node] = level.get_node("Markers").get_children()
	spots += level.get_node("NPCs").get_children()
	spots += level.find_children("*", "TeleportPortal", true, false)
	spots += level.find_children("*", "WorldLocation", true, false).filter(func(l: Node) -> bool: return (l as WorldLocation).kind != WorldLocation.Kind.SHOP and (l as WorldLocation).kind != WorldLocation.Kind.GUILD)
	var inside: Array[String] = []
	for spot in spots:
		for rect in rects:
			if rect.grow(0.5).has_point(_xz(spot as Node3D)):
				inside.append(str(level.get_path_to(spot)))
	_check(spots.size() >= 15 and inside.is_empty(), "%d markers, NPCs, portals and map places stay clear of every building %s" % [spots.size(), inside])


func _test_world_map() -> void:
	print("[World map]")
	var image := Image.load_from_file(ProjectSettings.globalize_path(WORLD_MAP))
	var service_rect := ExplorationService.WORLD_RECT
	var sample := func(at: Vector2) -> Color:
		var px := Vector2i(((at - service_rect.position) / service_rect.size * Vector2(image.get_size())).floor())
		return image.get_pixelv(px)
	for path in ["Buildings/CottageBlue", "Buildings/CottageOak", "Buildings/CottageFern"]:
		var spec: Array = MOVED[path]
		var now: Color = sample.call(spec[1])
		var before: Color = sample.call(spec[0] + (spec[0] - spec[1]).normalized() * 1.2)
		_check(_is_roof(now) and not _is_roof(before), "the baked map shows %s at its new place (%s), not the old one" % [path.get_file(), now])


func _is_roof(color: Color) -> bool:
	# bake_world_map.gd paints buildings in a dark terracotta (ROOF / ROOF_EDGE).
	return color.r > color.g + 0.1 and color.r > color.b + 0.15 and color.g < 0.4


func _test_walk_around() -> void:
	print("[Walk around every moved building and up to its door]")
	for path in MOVED:
		var rect := _building_rect(path).grow(1.3)
		# A loop through the four corners 1.3 m out, routed around yard props (woodpiles,
		# barrels) on a grid of the colliders, then walked with real input.
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position]
		var grid := _walk_grid(rect.grow(5.0))
		var route: Array[Vector2] = []
		for i in 4:
			var leg := _grid_path(grid, corners[i], corners[i + 1])
			if leg.is_empty():
				route.clear()
				break
			route.append_array(leg)
		var ok := not route.is_empty()
		if ok:
			player.teleport_to(Vector3(route[0].x, 0, route[0].y))
			await _frames(5)
			for i in range(1, route.size()):
				ok = await _steer_to(Vector3(route[i].x, 0, route[i].y), 0.45, 600)
				if not ok:
					break
		_check(ok, "walk all the way around %s (%d waypoints, stopped at %s)" % [path.get_file(), route.size(), player.global_position.snapped(Vector3.ONE * 0.1)])
		var door: Vector2 = (MOVED[path] as Array)[2]
		if door != Vector2.INF:
			player.teleport_to(Vector3(door.x, 0, door.y))
			await _frames(5)
			var house := _xz(level.get_node(path) as Node3D)
			ok = await _steer_to(Vector3(house.x, 0, house.y), 0.3, 240)
			var reached := rect.grow(-1.3).grow(0.6).has_point(_xz(player))
			_check(not ok and reached, "the lane ends at %s's door (walked from %s to the wall)" % [path.get_file(), door])


# --- Task 3: movement speed ---------------------------------------------------------------

func _test_movement_speeds() -> void:
	print("[Movement speed]")
	var movement := player.movement
	# Phase 5F: walk 4.5 m/s, run 7.5 m/s. Phase 5H: about 12% faster.
	_check(is_equal_approx(movement.walk_speed, 5.0) and is_equal_approx(movement.run_speed, 8.4), "walk %.1f m/s and run %.1f m/s (were 4.5 and 7.5)" % [movement.walk_speed, movement.run_speed])
	var walk_gain := movement.walk_speed / 4.5 - 1.0
	var run_gain := movement.run_speed / 7.5 - 1.0
	_check(walk_gain >= 0.1 and walk_gain <= 0.15 and run_gain >= 0.1 and run_gain <= 0.15, "both speeds rise by 10-15%% (walk %+d%%, run %+d%%)" % [roundi(walk_gain * 100), roundi(run_gain * 100)])
	_check(is_equal_approx(movement.get_animation_speed_scale(MovementComponent.State.WALK), movement.walk_speed / movement.walk_animation_speed)
			and is_equal_approx(movement.get_animation_speed_scale(MovementComponent.State.RUN), movement.run_speed / movement.run_animation_speed),
			"walk and run clips play at speed / the speed each clip was authored for")
	var combat := player.get_node("Combat") as CombatController
	_check(is_equal_approx(combat.dash_speed, 16.0) and is_equal_approx(combat.dash_duration, 0.2) and is_equal_approx(combat.dash_stamina_cost, 25.0) and is_equal_approx(combat.stamina_regen_per_second, 60.0),
			"dash distance, speed, cost and stamina regeneration are unchanged")


func _test_movement_feel() -> void:
	var character := player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	var movement := player.movement
	# Along the cleared market road: right + back is world +X with this camera.
	player.teleport_to(Vector3(6, 0, 1))
	await _frames(10)
	Input.action_press(&"move_right")
	Input.action_press(&"move_back")
	await _frames(45)
	var walk := player.get_horizontal_speed()
	var walk_rate := character.animation_player.get_playing_speed()
	# A one-shot (the interact reach) hands back to the walk at the walk's rate, not 1x.
	character.play_once(&"interact", 3.0)
	while character.is_playing_one_shot():
		await process_frame
	var resumed_rate := character.animation_player.get_playing_speed()
	var resumed_clip := character.current_clip
	Input.action_press(&"run")
	await _frames(45)
	var run := player.get_horizontal_speed()
	var run_rate := character.animation_player.get_playing_speed()
	Input.action_release(&"run")
	Input.action_release(&"move_right")
	Input.action_release(&"move_back")
	var stop_frames := 0
	while player.get_horizontal_speed() > movement.idle_threshold and stop_frames < 60:
		await physics_frame
		stop_frames += 1
	_check(absf(walk - movement.walk_speed) < 0.05, "walking reaches %.2f m/s" % walk)
	_check(absf(run - movement.run_speed) < 0.05, "running reaches %.2f m/s" % run)
	_check(is_equal_approx(walk_rate, movement.get_animation_speed_scale(MovementComponent.State.WALK)) and is_equal_approx(run_rate, movement.get_animation_speed_scale(MovementComponent.State.RUN)),
			"the walk clip plays at %.2fx and the run clip at %.2fx while moving" % [walk_rate, run_rate])
	_check(resumed_clip == &"move/Walking_A" and is_equal_approx(resumed_rate, walk_rate), "after a one-shot the walk resumes at %.2fx (%s)" % [resumed_rate, resumed_clip])
	# Acceleration and deceleration are unchanged, so starting and stopping stay as snappy.
	_check(stop_frames <= 15, "the courier still stops within a quarter second (%d frames)" % stop_frames)
	await _frames(20)
	_check(character.current_clip == &"general/Idle_A" and is_equal_approx(character.animation_player.get_playing_speed(), 1.0), "idle plays at normal speed after stopping")


# --- helpers -----------------------------------------------------------------------------

const GRID_CELL := 0.4
## Courier capsule radius plus a little room.
const BODY_CLEARANCE := 0.45


## Walkable cells (0.4 m) over area: blocked where a solid's footprint, grown by the
## courier's radius, covers the cell centre.
func _walk_grid(area: Rect2) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, Vector2i((area.size / GRID_CELL).ceil()))
	grid.cell_size = Vector2.ONE * GRID_CELL
	grid.offset = area.position + Vector2.ONE * GRID_CELL * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for shape in level.find_children("*", "CollisionShape3D", true, false):
		var body := shape.get_parent()
		if not body is PhysicsBody3D or body.name in ["Ground", "Boundary"] or body == player or not _at_surface(shape):
			continue
		var footprint := _footprint(shape).grow(BODY_CLEARANCE)
		if not footprint.intersects(area):
			continue
		var from := Vector2i(((footprint.position - area.position) / GRID_CELL).floor()).clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
		var to := Vector2i(((footprint.end - area.position) / GRID_CELL).ceil()).clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
		for x in range(from.x, to.x + 1):
			for y in range(from.y, to.y + 1):
				if footprint.has_point(grid.offset + Vector2(x, y) * GRID_CELL):
					grid.set_point_solid(Vector2i(x, y))
	return grid


## World XZ waypoints from a to b over grid (b's nearest free cell); empty when unreachable.
func _grid_path(grid: AStarGrid2D, a: Vector2, b: Vector2) -> Array[Vector2]:
	var cells: Array[Vector2i] = []
	for at in [a, b]:
		var cell := Vector2i(((at - grid.offset) / GRID_CELL).round()).clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
		var best := cell
		var radius := 0
		while grid.is_point_solid(best) and radius < 8:
			radius += 1
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					var c := (cell + Vector2i(x, y)).clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
					if not grid.is_point_solid(c) and grid.is_point_solid(best):
						best = c
		cells.append(best)
	var out: Array[Vector2] = []
	var points := grid.get_point_path(cells[0], cells[1])
	# Every third cell is plenty for the steering helper.
	for i in points.size():
		if i % 3 == 0 or i == points.size() - 1:
			out.append(points[i])
	return out

func _gap(a: String, b: String) -> float:
	var ra := _building_rect(a)
	var rb := _building_rect(b)
	var dx := maxf(0.0, maxf(ra.position.x - rb.end.x, rb.position.x - ra.end.x))
	var dz := maxf(0.0, maxf(ra.position.y - rb.end.y, rb.position.y - ra.end.y))
	return Vector2(dx, dz).length()


## True for an active collider the courier can meet on the village surface. XZ footprints
## alone would also count rooms built below the village (an underground level) and switched-off
## bodies (a felled tree's trunk).
func _at_surface(shape: Node) -> bool:
	var body := shape.get_parent()
	return (shape as Node3D).global_position.y > SURFACE_DEPTH and body.can_process()


## World XZ bounds of a building's colliders.
func _building_rect(path: String) -> Rect2:
	var rect := Rect2()
	var first := true
	for shape in (level.get_node(path) as Node).find_children("*", "CollisionShape3D", true, false):
		var footprint := _footprint(shape)
		if footprint.size == Vector2.ZERO:
			continue
		rect = footprint if first else rect.merge(footprint)
		first = false
	return rect


## World XZ bounds of a box, cylinder or capsule collider.
func _footprint(node: Node) -> Rect2:
	var cs := node as CollisionShape3D
	var half := Vector3.ZERO
	if cs.shape is BoxShape3D:
		half = (cs.shape as BoxShape3D).size * 0.5
	elif cs.shape is CylinderShape3D:
		half = Vector3.ONE * (cs.shape as CylinderShape3D).radius
	elif cs.shape is CapsuleShape3D:
		half = Vector3.ONE * (cs.shape as CapsuleShape3D).radius
	elif cs.shape is SphereShape3D:
		half = Vector3.ONE * (cs.shape as SphereShape3D).radius
	else:
		return Rect2()
	var rect := Rect2()
	for i in 4:
		var corner := cs.global_transform * Vector3(half.x * (1 if i & 1 else -1), 0, half.z * (1 if i & 2 else -1))
		rect = Rect2(corner.x, corner.z, 0, 0) if i == 0 else rect.expand(Vector2(corner.x, corner.z))
	return rect


func _steer_to(goal: Vector3, radius: float, max_frames: int) -> bool:
	return await _steer_until(goal, func() -> bool:
		var to := goal - player.global_position
		return Vector2(to.x, to.z).length() <= radius, max_frames)


## Walks the courier towards goal with real input until done() is true. False when it got
## stuck (no progress for two seconds) or ran out of frames first.
func _steer_until(goal: Vector3, done: Callable, max_frames: int) -> bool:
	var stuck := 0
	var last := player.global_position
	var ok := false
	for i in max_frames:
		if done.call():
			ok = true
			break
		var to := goal - player.global_position
		to.y = 0
		if to.length() < 0.1:
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
	await physics_frame
	return ok or done.call()


func _press(positive: StringName, negative: StringName, amount: float) -> void:
	Input.action_release(positive)
	Input.action_release(negative)
	if amount > 0.05:
		Input.action_press(positive, amount)
	elif amount < -0.05:
		Input.action_press(negative, -amount)
