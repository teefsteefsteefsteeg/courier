extends SceneTree
## Renders the weapon elemental VFX in the real village (GPU window, NOT --headless) to
## docs/validation/weapon-elemental-vfx/:
##   passive_<weapon>.png         close-ups of the held weapon at +0..+5 (6 frames each, 4
##                                weapons = 24 combinations), each frame a real render
##   gameplay_<weapon>_plus5.png  the +5 weapon from the default gameplay camera
##   moving_<weapon>_plus5.png    the same while running (trails, world-space particles)
##   attack_<weapon>_plus<n>.png  a normal attack (Space) at +3 and +5: weapon-specific
##                                active effects, no ultimate
##   ultimate_<weapon>_<n>.png    the +5 ultimate (C) in frames as it travels / expands /
##                                strikes, with training dummies (forest slimes, frozen)
##   switch_*.png                 effects follow a weapon switch (Q) and a teleport
## SaveGame is removed and UISettings does not persist.
##   godot --path . --resolution 1600x900 --script res://tests/capture_weapon_elemental_vfx.gd -- <output_dir>

const ARENA := Vector3(5.6, 0, -11.0)
const WEAPONS := [[&"steel_sword", "sword"], [&"battle_axe", "axe"], [&"hunting_bow", "bow"], [&"magic_staff", "staff"]]
const SLIME := "res://scenes/gameplay/combat/forest_slime.tscn"
const CROP := 400

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var inventory: CourierInventory
var visuals: EnhancementVisuals
var out_dir: String
var problems: PackedStringArray = []
var dummies: Array[Node3D] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://docs/validation/weapon-elemental-vfx"
	DirAccess.make_dir_recursive_absolute(out_dir)
	UISettings.persist = false
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	rig.set_process_unhandled_input(false)
	inventory = CourierInventory.find(self)
	visuals = EnhancementVisuals.find(self)
	await _wait(40)
	for entry in WEAPONS:
		inventory.add_item(inventory.get_definition(entry[0]))
	for entry in WEAPONS:
		await _passive(entry[0], entry[1])
	if has_method(&"_actives"):
		await call(&"_actives")
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


## Close-ups at +0..+5 in one sheet, then the +5 from the gameplay camera, then running.
func _passive(id: StringName, label: String) -> void:
	inventory.equip(id)
	player.teleport_to(ARENA)
	player.rotation.y = 0.0
	await _wait(10)
	var frames: Array[Image] = []
	for lvl in range(0, 6):
		inventory.set_enhancement(id, lvl)
		rig.min_zoom_size = 2.0
		rig.set_zoom(5.6)
		rig.camera.size = 5.6
		rig.snap_to_target()
		await _wait(24)
		var glow := visuals.weapon_glow
		_expect((glow == null) == (lvl == 0), "%s +%d effect %s" % [label, lvl, glow.elements if glow != null else []])
		frames.append(await _crop())
	_sheet(frames, "passive_%s.png" % label, label)
	rig.min_zoom_size = 8.0
	rig.set_zoom(12.0)
	rig.camera.size = 12.0
	rig.snap_to_target()
	await _wait(20)
	await _shot("gameplay_%s_plus5.png" % label)
	Input.action_press(&"move_back")
	Input.action_press(&"run")
	await _wait(24)
	await _shot("moving_%s_plus5.png" % label)
	Input.action_release(&"move_back")
	Input.action_release(&"run")
	await _wait(10)


## A square around the held weapon (its middle projected to the screen).
func _crop() -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var held := _held()
	var at := held.global_position if held != null else player.global_position + Vector3.UP
	if held != null:
		var box := EnhancementGlow.local_bounds(held)
		at = held.global_transform * box.get_center()
	var centre := Vector2i(rig.camera.unproject_position(at))
	var corner := (centre - Vector2i(CROP, CROP) / 2).clamp(Vector2i.ZERO, Vector2i(image.get_width() - CROP, image.get_height() - CROP))
	return image.get_region(Rect2i(corner, Vector2i(CROP, CROP)))


func _held() -> Node3D:
	var found := player.find_children("*", "KayKitCharacter", true, false)
	return (found[0] as KayKitCharacter).get_held_item_node() if not found.is_empty() else null


func _sheet(frames: Array[Image], file: String, label: String) -> void:
	var sheet := Image.create(CROP * frames.size(), CROP, false, frames[0].get_format())
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, Vector2i(CROP, CROP)), Vector2i(CROP * i, 0))
	var path := out_dir.path_join(file)
	sheet.save_png(path)
	print("saved ", path, " (", label, " +0..+5)")


## Normal attacks at +3 and +5, then the +5 ultimate in frames, for every weapon, aimed
## south over the plaza at frozen forest slimes (training dummies).
func _actives() -> void:
	var ultimates := WeaponUltimates.find(self)
	var aim := Vector3.BACK
	var side := aim.cross(Vector3.UP)
	for entry in WEAPONS:
		var id: StringName = entry[0]
		var label: String = entry[1]
		_clear_dummies()
		for spot in [[3.0, 0.0], [6.0, 2.5], [8.0, -2.5], [11.0, 1.0]]:
			_dummy(ARENA + aim * float(spot[0]) + side * float(spot[1]))
		inventory.equip(id)
		for lvl in [3, 5]:
			inventory.set_enhancement(id, lvl)
			player.teleport_to(ARENA)
			await _wait(4)
			player.facing.visual_root.rotation.y = FacingComponent.yaw_for_direction(aim)
			rig.set_zoom(13.0)
			rig.camera.size = 13.0
			rig.snap_to_target()
			await _wait(20)
			var combat := CombatController.find_on(player)
			combat.try_attack(aim)
			await _wait(9 if label in ["sword", "axe"] else 14)
			await _shot("attack_%s_plus%d.png" % [label, lvl])
			await _wait(40)
		# The ultimate, with the real C key, in three frames.
		ultimates.cooldowns.clear()
		rig.set_zoom(17.0)
		rig.camera.size = 17.0
		rig.snap_to_target()
		await _wait(10)
		await _key(KEY_C)
		_expect(ultimates.get_cooldown_remaining() > 0.0, "%s +5: C released the ultimate" % label)
		var gaps := {"sword": [8, 14, 16], "axe": [6, 14, 30], "bow": [10, 14, 22], "staff": [30, 40, 50]}
		var index := 0
		for gap: int in gaps[label]:
			await _wait(gap)
			index += 1
			await _shot("ultimate_%s_%d.png" % [label, index])
		await _wait(90)
	_clear_dummies()
	# Weapon switching: the pickaxe in hand (no effect), Q back to the +5 sword (effect back).
	inventory.add_item(inventory.get_definition(&"miner_pickaxe"))
	inventory.equip(&"steel_sword")
	inventory.set_enhancement(&"steel_sword", 5)
	inventory.equip(&"miner_pickaxe")
	player.teleport_to(ARENA)
	rig.set_zoom(10.0)
	rig.camera.size = 10.0
	rig.snap_to_target()
	await _wait(20)
	_expect(visuals.weapon_glow == null, "a tool in hand shows no weapon effect")
	await _shot("switch_1_pickaxe.png")
	await _key(KEY_Q)
	await _wait(20)
	_expect(visuals.weapon_glow != null and visuals.weapon_glow.level == 5, "Q back to the +5 sword brings its inferno back")
	await _shot("switch_2_q_back_to_sword_plus5.png")


func _dummy(at: Vector3) -> void:
	var slime := (load(SLIME) as PackedScene).instantiate() as Enemy
	slime.simulate = false
	level.add_child(slime)
	slime.global_position = at
	slime.health.max_health = 5000.0
	slime.health.reset()
	dummies.append(slime)


func _clear_dummies() -> void:
	for dummy in dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	dummies.clear()


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(file)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
