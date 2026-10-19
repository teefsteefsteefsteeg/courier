extends SceneTree
## Phase 5F armory checks: the KayKit weapons are imported lean and share one
## material, the armory location sits in the village with its hall, displays,
## facade and weaponsmith, every display merges, the merchant raises
## `shop_requested`, nothing solid overlaps other buildings or gameplay spots,
## and the courier can walk to the counter from the plaza and the forest road.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5f_armory_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const LOCATION := "res://scenes/locations/armory.tscn"
const WEAPONS := "res://assets/models/kaykit_weapons"
const WEAPON_MATERIAL := "res://assets/materials/armory/weapons.tres"
const PROPS := "res://scenes/props/armory"
const ARMORY_AT := Vector3(4.4, 0, -16.6)
## Weapon kinds a weapon shop must show (model file prefixes).
const KINDS := ["sword", "shield", "axe", "hammer", "spear", "halberd", "dagger", "bow", "staff"]
const KEEP_CLEAR := 1.2
## Walks to the counter: start, waypoints.
const WALKS := {
	"plaza": [Vector3(0, 0, 1.5), Vector3(3.6, 0, -6.0), Vector3(5.9, 0, -11.0)],
	"forest road": [Vector3(11.4, 0, -15.6), Vector3(8.4, 0, -11.6)],
}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var armory: Armory


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_kit()
	_test_props()
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	for i in 10:
		await physics_frame
	armory = level.get_node_or_null("Armory") as Armory
	_check(armory != null and armory.scene_file_path == LOCATION, "village instances %s as an Armory" % LOCATION)
	if armory != null:
		_test_location()
		_test_merchant()
		_test_clearances()
		await _test_walks()
	print("\n=== Phase 5F armory tests: %d passed, %d failed ===" % [_passes, _failures])
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
	print("[KayKit weapons]")
	_check(FileAccess.get_file_as_string(WEAPONS.path_join("License.txt")).contains("Creative Commons Zero"), "weapons keep their CC0 License.txt")
	var texture := load(WEAPONS.path_join("weapons_bits_texture.png")) as Texture2D
	_check(texture != null and texture.get_width() <= 1024, "weapon texture capped at 1024 px")
	var used := ""
	for file in DirAccess.get_files_at(PROPS):
		if file.ends_with(".tscn"):
			used += FileAccess.get_file_as_string(PROPS.path_join(file))
	used += FileAccess.get_file_as_string(LOCATION)
	var shared := true
	var unused: Array[String] = []
	for file in DirAccess.get_files_at(WEAPONS):
		if not file.ends_with(".gltf"):
			continue
		var path := WEAPONS.path_join(file)
		if not used.contains(path):
			unused.append(file)
		var weapon := (load(path) as PackedScene).instantiate()
		for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
			for s in (mesh as MeshInstance3D).mesh.get_surface_count():
				var material := (mesh as MeshInstance3D).mesh.surface_get_material(s)
				shared = shared and material != null and material.resource_path == WEAPON_MATERIAL
		weapon.free()
	_check(unused.is_empty(), "every imported weapon is on display (%s unused)" % [unused])
	_check(shared, "every weapon uses the shared weapons material")


func _test_props() -> void:
	print("[Display props]")
	var kinds := {}
	var total := 0
	for file in DirAccess.get_files_at(PROPS):
		if not file.ends_with(".tscn"):
			continue
		var prop := (load(PROPS.path_join(file)) as PackedScene).instantiate()
		_check(prop is MergedProp and prop.has_node(^"Model"), "%s is a MergedProp" % file)
		for child in prop.get_node(^"Model").get_children():
			if child.scene_file_path.begins_with(WEAPONS):
				total += 1
				for kind in KINDS:
					if child.scene_file_path.get_file().begins_with(kind):
						kinds[kind] = true
		prop.free()
	var location := (load(LOCATION) as PackedScene).instantiate()
	for child in location.get_node(^"Facade").get_children():
		if child.scene_file_path.begins_with(WEAPONS):
			total += 1
	location.free()
	_check(total >= 20, "the armory shows %d weapons" % total)
	var missing := KINDS.filter(func(kind: String) -> bool: return not kinds.has(kind))
	_check(missing.is_empty(), "swords, shields, axes, hammers, spears, a halberd, daggers, a bow and staffs on display (%s missing)" % [missing])


func _test_location() -> void:
	print("[Armory location]")
	_check(armory.global_position.is_equal_approx(ARMORY_AT) and armory.global_basis.is_equal_approx(Basis.IDENTITY), "armory stands north of the plaza, facing it")
	var hall := armory.get_node_or_null(^"Hall") as MedievalBuilding
	_check(hall != null and hall.merge_model and hall.has_node(^"Model/Merged"), "hall is a merged MegaKit building")
	_check(hall != null and hall.get_node_or_null(^"CameraOccluder") is CameraOccluder, "hall fades for the camera")
	for path in ["Displays/PolearmRack", "Displays/SwordRack", "Displays/DisplayTable", "Displays/MerchantCounter", "Displays/WeaponBarrel", "Facade/GableEmblem"]:
		var prop := armory.get_node_or_null(path)
		var surfaces := 0
		if prop != null:
			for mesh in prop.find_children("*", "MeshInstance3D", true, false):
				surfaces += (mesh as MeshInstance3D).mesh.get_surface_count()
		_check(prop is MergedProp and prop.has_node(^"Model/Merged") and surfaces <= 6, "%s merged (%d surfaces)" % [path, surfaces])
	var sign := armory.get_node_or_null(^"Facade/SignText") as Label3D
	_check(sign != null and sign.text == "ARMORY", "shop sign reads ARMORY")
	for marker in ["Markers/MerchantSpot", "Markers/ShopFront", "Markers/Entrance"]:
		_check(armory.get_node_or_null(marker) is Marker3D, "has %s" % marker)
	_check(armory.get_shop_front() != null and armory.get_entrance() != null, "shop front and entrance accessors resolve")


func _test_merchant() -> void:
	print("[Weaponsmith]")
	var merchant := armory.merchant
	_check(merchant != null and merchant.npc_id == &"armory_merchant" and merchant.npc_name == "Weaponsmith Brenna", "weaponsmith Brenna stands behind the counter")
	if merchant == null:
		return
	_check(merchant.global_position.distance_to(armory.get_node(^"Markers/MerchantSpot").global_position) < 0.05, "merchant on MerchantSpot")
	var requests: Array[Node] = []
	armory.shop_requested.connect(func(interactor: Node) -> void: requests.append(interactor))
	merchant.interactable.interact(player)
	_check(requests == [player] and merchant.interaction_count == 1, "talking to the merchant raises shop_requested")


func _test_clearances() -> void:
	print("[Clearances]")
	var own: Array[Rect2] = []
	for shape in armory.find_children("*", "CollisionShape3D", true, false):
		var cs := shape as CollisionShape3D
		if cs.get_parent() is PhysicsBody3D and not (cs.get_parent() is NPC):
			own.append(_footprint(cs))
	_check(own.size() >= 6, "armory has %d solid footprints" % own.size())
	var overlaps: Array[String] = []
	for shape in level.find_children("*", "CollisionShape3D", true, false):
		var cs := shape as CollisionShape3D
		var body := cs.get_parent()
		if not (body is PhysicsBody3D) or body.name in ["Ground", "Boundary"] or armory.is_ancestor_of(cs) or body == player:
			continue
		# Only surface solids can collide with the armory: rooms built more than 3 m below the
		# village (an underground level) share its XZ footprint without touching it.
		if cs.global_position.y < -3.0:
			continue
		var rect := _footprint(cs)
		for mine in own:
			if mine.intersects(rect):
				overlaps.append(str(level.get_path_to(body)))
	_check(overlaps.is_empty(), "no armory collider overlaps another solid (%s)" % [overlaps])
	# WorldLocation markers are map-icon anchors placed on the building itself, not places
	# the courier stands, so they are exempt.
	var spots := level.find_children("*", "Marker3D", true, false).filter(func(m: Node) -> bool: return not armory.is_ancestor_of(m) and not m is WorldLocation)
	spots += level.get_node("NPCs").get_children()
	var near: Array[String] = []
	for spot in spots:
		var at := Vector2((spot as Node3D).global_position.x, (spot as Node3D).global_position.z)
		for mine in own:
			if mine.grow(KEEP_CLEAR).has_point(at):
				near.append(str(level.get_path_to(spot)))
	_check(near.is_empty(), "armory keeps %.1f m from NPCs and gameplay markers (%s)" % [KEEP_CLEAR, near])


func _test_walks() -> void:
	print("[Walk to the counter]")
	var front := armory.get_shop_front().global_position
	var detector := player.get_node(^"InteractionDetector") as InteractionDetector
	for name in WALKS:
		var points: Array = WALKS[name]
		player.teleport_to(points[0])
		await _frames(5)
		var ok := true
		for i in range(1, points.size()):
			ok = ok and await _steer_to(points[i], 0.8, 900)
		ok = ok and await _steer_to(front, 0.45, 600)
		_check(ok, "walk from the %s to the counter (stopped at %s)" % [name, player.global_position.snapped(Vector3.ONE * 0.1)])
		await _frames(3)
		_check(detector.focused == armory.merchant.interactable, "prompt focuses the weaponsmith after walking from the %s" % name)


# --- helpers ------------------------------------------------------------------

## XZ footprint of a box/cylinder/capsule collider (axis-aligned bounds).
func _footprint(cs: CollisionShape3D) -> Rect2:
	var half := Vector3.ONE * 0.5
	if cs.shape is BoxShape3D:
		half = (cs.shape as BoxShape3D).size * 0.5
	elif cs.shape is CylinderShape3D:
		half = Vector3.ONE * (cs.shape as CylinderShape3D).radius
	elif cs.shape is CapsuleShape3D:
		half = Vector3.ONE * (cs.shape as CapsuleShape3D).radius
	elif cs.shape is SphereShape3D:
		half = Vector3.ONE * (cs.shape as SphereShape3D).radius
	var box := cs.global_transform * AABB(-half, half * 2)
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
