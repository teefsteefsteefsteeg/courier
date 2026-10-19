extends SceneTree
## Renders Phase 8 milestone 3 (weapon enhancement tiers) in the real village (GPU window,
## NOT --headless): the Steel Sword at +1..+5 close up, the same sword hitting a training
## dummy at each tier (real attack key, photographed just after the hit), and the tiers on
## the axe, bow and staff. SaveGame is removed and UISettings does not persist.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_weapon_vfx.gd -- <output_dir>

const ARENA := Vector3(5.6, 0, -11.0)

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var inventory: CourierInventory
var combat: CombatController
var visuals: EnhancementVisuals
var out_dir: String
var problems: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase8")
	DirAccess.make_dir_recursive_absolute(out_dir)
	UISettings.persist = false
	UISettings.set_value(UISettings.SHOW_ENHANCEMENT_VFX, true)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	rig.min_zoom_size = 3.0
	rig.set_process_unhandled_input(false)
	await _wait(40)
	inventory = CourierInventory.find(self)
	combat = CombatController.find_on(player)
	visuals = EnhancementVisuals.find(self)
	for id in [&"steel_sword", &"battle_axe", &"hunting_bow", &"magic_staff"]:
		inventory.add_item(inventory.get_definition(id))
	inventory.equip(&"steel_sword")

	for lvl in range(1, Enhancement.MAX_LEVEL + 1):
		inventory.set_enhancement(&"steel_sword", lvl)
		await _goto(ARENA, 3.6)
		await _seconds(0.7)
		_expect(visuals.weapon_glow != null and visuals.weapon_glow.level == lvl, "steel sword +%d effect (%s)" % [lvl, visuals.weapon_glow.elements if visuals.weapon_glow else []])
		await _shot("%d_sword_tier%d_%s" % [12 + lvl, lvl, EnhancementGlow.TIER_NAMES[lvl].to_lower().replace(" ", "_")])

	# Hits at each tier (the courier swings along its facing; the dummy stands there).
	await _goto(ARENA, 5.5)
	var aim := combat.get_aim_direction()
	var dummy := _dummy(player.global_position + aim * 1.3)
	await _wait(5)
	for lvl in range(1, Enhancement.MAX_LEVEL + 1):
		inventory.set_enhancement(&"steel_sword", lvl)
		await _seconds(0.9)
		await _attack_key()
		while combat.is_melee_pending():
			await process_frame
		await _seconds(0.08)
		await _shot("%d_sword_tier%d_hit" % [17 + lvl, lvl])
	dummy.queue_free()

	for case in [[&"battle_axe", 5, "23_axe_tier5"], [&"hunting_bow", 4, "24_bow_tier4"], [&"magic_staff", 3, "25_staff_tier3"], [&"battle_axe", 2, "26_axe_tier2"]]:
		inventory.equip(case[0])
		inventory.set_enhancement(case[0], case[1])
		await _goto(ARENA, 3.8)
		await _seconds(0.7)
		_expect(visuals.weapon_glow != null and visuals.weapon_glow.level == case[1], "%s +%d effect" % [case[0], case[1]])
		await _shot(case[2])
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _attack_key() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame


func _dummy(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = CombatController.ENEMY_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.35
	capsule_mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.45, 0.28)
	capsule_mesh.material = material
	mesh.mesh = capsule_mesh
	mesh.position = Vector3(0, 0.9, 0)
	body.add_child(mesh)
	var health := CombatHealth.new()
	health.max_health = 100000.0
	body.add_child(health)
	level.add_child(body)
	body.global_position = at
	return body


func _goto(at: Vector3, zoom: float) -> void:
	player.teleport_to(at)
	rig.set_zoom(zoom)
	rig.snap_to_target()
	await _wait(25)


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
