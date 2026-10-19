extends SceneTree
## Renders Phase 7 Milestone C in the real village (GPU window, NOT --headless): weapon
## enhancement effects +1..+5, armor auras, the "Show enhancement effects" toggle off and
## on, Brenna's Enhance section, and sword / axe swings photographed the moment the hit
## lands (arc at its fullest, impact flash on the dummy). SaveGame is removed and
## UISettings does not persist, so the real save and settings are never touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase7_enhancement.gd -- <output_dir>

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
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase7")
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
	# Stray mouse-wheel input on the capture window must not change the zoom.
	rig.set_process_unhandled_input(false)
	await _wait(30)
	inventory = CourierInventory.find(self)
	combat = CombatController.find_on(player)
	visuals = EnhancementVisuals.find(self)
	var wallet := CourierWallet.find(self)
	wallet.add_gold(2000)
	for id in [&"iron_sword", &"steel_sword", &"battle_axe", &"wooden_shield", &"leather_vest", &"iron_mail"]:
		inventory.add_item(inventory.get_definition(id))
	inventory.add_material(inventory.get_material_definition(&"iron_ore"), 12)

	# Weapon effects, one level per shot, close up.
	inventory.equip(&"steel_sword")
	for lvl in range(1, Enhancement.MAX_LEVEL + 1):
		inventory.set_enhancement(&"steel_sword", lvl)
		await _goto(ARENA, 4.0)
		await _seconds(0.5)
		_expect(visuals.weapon_glow != null and visuals.weapon_glow.level == lvl, "weapon glow +%d" % lvl)
		await _shot("%d_weapon_enhancement_plus%d" % [22 + lvl, lvl])

	# Armor auras +1, +3, +5 (sword back to +0 so only the armor shows).
	inventory.set_enhancement(&"steel_sword", 0)
	inventory.equip(&"iron_mail")
	var index := 28
	for lvl in [1, 3, 5]:
		inventory.set_enhancement(&"iron_mail", lvl)
		await _goto(ARENA, 5.0)
		await _seconds(1.2)
		_expect(visuals.armor_aura != null, "armor aura +%d" % lvl)
		await _shot("%d_armor_enhancement_plus%d" % [index, lvl])
		index += 1

	# Everything at +5 at the normal play zoom, then the toggle off and on.
	inventory.set_enhancement(&"steel_sword", 5)
	inventory.equip(&"wooden_shield")
	inventory.set_enhancement(&"wooden_shield", 3)
	await _goto(ARENA, 12.0)
	await _seconds(1.0)
	await _shot("31_full_set_plus5_play_zoom")
	var equipment := level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	var defense := combat.defense
	var damage := combat.melee_damage
	equipment.open()
	equipment.select_item(&"iron_mail")
	await _wait(6)
	await _shot("32_inventory_effects_toggle_on")
	equipment.vfx_toggle.button_pressed = false
	await _wait(6)
	await _shot("33_inventory_effects_toggle_off")
	equipment.close()
	await _goto(ARENA, 5.0)
	await _seconds(0.5)
	_expect(visuals.weapon_glow == null and visuals.armor_aura == null, "effects hidden")
	_expect(is_equal_approx(defense, combat.defense) and is_equal_approx(damage, combat.melee_damage), "bonuses kept while hidden (defense %.0f, damage %.0f)" % [combat.defense, combat.melee_damage])
	await _shot("34_effects_hidden_bonuses_kept")
	UISettings.set_value(UISettings.SHOW_ENHANCEMENT_VFX, true)
	await _seconds(0.5)

	# Brenna's Enhance section.
	var armory := level.get_node("Armory") as Armory
	await _goto(armory.get_shop_front().global_position, 10.0)
	var shop := level.find_children("*", "ShopUI", true, false)[0] as ShopUI
	shop.open(armory.merchant.get_node("ShopMerchant") as Merchant, player)
	await _wait(4)
	inventory.set_enhancement(&"leather_vest", 0)
	shop.enhance_item(&"leather_vest")
	var row := shop.enhance_rows[&"leather_vest"]["row"] as Control
	var scroll := row.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(shop.enhance_rows[&"iron_mail"]["row"] as Control)
	await _wait(6)
	_expect(inventory.get_enhancement(&"leather_vest") == 1, "Brenna enhanced the vest")
	await _shot("35_brenna_enhance_section")
	shop.close()
	await _wait(4)

	# Swings photographed the frame the hit lands.
	inventory.set_enhancement(&"iron_mail", 0)
	await _goto(ARENA, 6.0)
	# The dummy stands where the courier faces: the attack key swings that way.
	var aim := combat.get_aim_direction()
	var dummy := _dummy(player.global_position + aim * 1.3)
	await _wait(5)
	await _swing_shot(&"steel_sword", aim, dummy, "36_sword_swing_at_hit")
	await _seconds(0.1)
	await _shot("37_sword_impact_flash")
	await _seconds(0.8)
	await _swing_shot(&"battle_axe", aim, dummy, "38_axe_chop_at_hit")
	await _seconds(0.1)
	await _shot("39_axe_impact_flash")

	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _swing_shot(weapon: StringName, aim: Vector3, dummy: Node3D, name: String) -> void:
	inventory.equip(weapon)
	inventory.set_enhancement(weapon, 5 if weapon == &"steel_sword" else 3)
	await _seconds(1.0)
	var health := CombatHealth.find_on(dummy)
	var before := health.get_health()
	var started := [false]
	var on_start := func(_d: Vector3, _h: bool) -> void: started[0] = true
	combat.melee_started.connect(on_start)
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = &"combat_magic_bolt"
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	combat.melee_started.disconnect(on_start)
	_expect(started[0], "%s swings on the attack key" % weapon)
	while combat.is_melee_pending():
		await process_frame
	_expect(health.get_health() < before, "%s hit the dummy" % weapon)
	await _shot(name)


func _dummy(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TrainingDummy"
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
	health.max_health = 5000.0
	body.add_child(health)
	level.add_child(body)
	body.global_position = at
	return body


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _goto(at: Vector3, zoom: float) -> void:
	player.teleport_to(at)
	rig.set_zoom(zoom)
	rig.snap_to_target()
	await _wait(20)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
