extends SceneTree
## Rendered evidence for Phase 8 milestone 1 (recovery brief) in the real village (GPU
## window, NOT --headless), to docs/validation/phase8/:
##   70 HUD: HP, MP and rage bars, buffs, provisions bar     71 the Food Market stall
##   72 the Food Market shop                                  73 inventory Provisions view
##   74 hurt by a real slime   75 the same HP regenerated     76 critical hit
##   77-79 Flame Slash: burning ground, scorch, explosion     80-82 Earthquake
##   83-85 Thunder Arrow: lightning from the sky, chain       86-88 Arcane Storm
##   89 staff cast circle and rage READY
## SaveGame is removed (the player's save is never touched); UISettings does not persist.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_vitals.gd -- <output_dir>

const ARENA := Vector3(5.6, 0, -11.0)
const AIM := Vector3.BACK
const SLIME := "res://scenes/gameplay/combat/forest_slime.tscn"

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var inventory: CourierInventory
var vitals: CourierVitals
var ultimates: WeaponUltimates
var combat: CombatController
var out_dir: String
var problems: PackedStringArray = []
var dummies: Array[Node3D] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "res://docs/validation/phase8"
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
	vitals = CourierVitals.find(self)
	ultimates = WeaponUltimates.find(self)
	combat = CombatController.find_on(player)
	await _wait(40)
	for id in [&"steel_sword", &"battle_axe", &"hunting_bow", &"magic_staff"]:
		inventory.add_item(inventory.get_definition(id))
	CourierWallet.find(self).restore(800, 20)

	# Food Market and shop.
	var market := level.find_child("FoodMarket", true, false) as ToolStall
	player.teleport_to(market.get_shop_front().global_position + Vector3(0.5, 0, 1.5))
	rig.snap_to_target()
	await _wait(30)
	await _shot("71_food_market_stall.png")
	player.teleport_to(market.get_shop_front().global_position)
	await _wait(20)
	await _key(KEY_E)
	await _wait(10)
	var shop := level.find_children("*", "ShopUI", true, false)[0] as ShopUI
	_expect(shop.is_open(), "the Food Market shop opens with E")
	for id in [&"health_potion", &"mana_potion", &"roast_ham", &"cheese_wheel", &"warriors_ale", &"berserker_draught", &"bread_loaf", &"ironbark_stew"]:
		shop.buy_goods(id, 3)
	await _wait(6)
	await _shot("72_food_market_shop.png")
	shop.close()
	await _wait(6)
	# Inventory, Provisions view.
	await _key(KEY_TAB)
	await _key(KEY_Q)
	await _key(KEY_Q)
	var equipment := level.find_child("EquipmentUI", true, false) as EquipmentUI
	equipment.select_consumable(&"roast_ham")
	await _wait(6)
	_expect(equipment.view == EquipmentUI.View.PROVISIONS, "Provisions view")
	await _shot("73_inventory_provisions.png")
	await _key(KEY_TAB)

	# HUD with buffs, MP spent and some rage.
	player.teleport_to(ARENA)
	rig.snap_to_target()
	vitals.consume(&"roast_ham")
	vitals.consume(&"warriors_ale")
	vitals.spend(35.0)
	await _wait(20)
	await _shot("70_hud_hp_mp_rage_buffs.png")

	# Regeneration after a real slime's hits.
	vitals.buffs.clear()
	vitals.heals.clear()
	vitals._apply_buffs()
	var slime := _dummy(ARENA + Vector3(1.5, 0, 0.5), 40.0, true)
	var waited := 0
	while combat.health.get_health() > 75.0 and waited < 600:
		await process_frame
		waited += 1
	slime.health.apply_damage(9999.0)
	await _wait(30)
	var hurt := combat.health.get_health()
	await _shot("74_hurt_by_slime.png")
	await _seconds(vitals.hp_regen_delay + 6.0)
	_expect(combat.health.get_health() > hurt, "HP regenerated (%.0f -> %.0f)" % [hurt, combat.health.get_health()])
	await _shot("75_hp_regenerated.png")
	await _clear()

	# Critical hit (Berserker Draught).
	await _face()
	inventory.equip(&"steel_sword")
	inventory.set_enhancement(&"steel_sword", 2)
	vitals.consume(&"berserker_draught")
	combat.crit_chance = 1.0
	_dummy(_at(1.3))
	await _wait(10)
	combat.try_attack(AIM)
	await _seconds(0.25)
	await _shot("76_critical_hit.png")
	vitals.buffs.clear()
	vitals._apply_buffs()
	await _clear()

	# Ultimates.
	await _ultimate(&"steel_sword", [[0.3, "77_flame_slash_burning_ground.png"], [0.55, "78_flame_slash_explosion.png"], [1.2, "79_flame_slash_scorched_trail.png"]], [_at(5.0), _at(9.0, 1.0)])
	await _ultimate(&"battle_axe", [[0.12, "80_earthquake_rings.png"], [0.45, "81_earthquake_rocks.png"], [1.6, "82_earthquake_fissures.png"]], [_at(3.0), _at(5.0, -2.0), _at(4.5, 2.5)])
	await _ultimate(&"hunting_bow", [[0.22, "83_thunder_arrow_strike.png"], [0.42, "84_thunder_arrow_chain.png"], [0.75, "85_thunder_arrow_scorch.png"]], [_at(6.0), _at(8.0, 2.0), _at(9.5, -1.5)])
	await _ultimate(&"magic_staff", [[0.45, "86_arcane_storm_circle.png"], [1.25, "87_arcane_storm_strike.png"], [2.1, "88_arcane_storm_strikes.png"]], [_at(4.0), _at(5.0, 1.5)])

	# Cast circle with the staff, rage READY on the HUD.
	await _face()
	inventory.equip(&"magic_staff")
	inventory.set_enhancement(&"magic_staff", 5)
	vitals.add_rage(100.0)
	await _wait(6)
	combat.try_attack(AIM)
	await _seconds(0.12)
	await _shot("89_staff_cast_circle_rage_ready.png")
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _ultimate(id: StringName, shots: Array, targets: Array) -> void:
	await _face()
	inventory.equip(id)
	inventory.set_enhancement(id, 5)
	for at: Vector3 in targets:
		_dummy(at)
	vitals.add_rage(100.0)
	vitals.restore_mana(100.0)
	rig.set_zoom(16.0)
	await _wait(20)
	_expect(ultimates.use(), "%s ultimate released" % id)
	var elapsed := 0.0
	for shot: Array in shots:
		await _seconds(float(shot[0]) - elapsed)
		elapsed = float(shot[0])
		await _shot(shot[1])
	await _seconds(2.5)
	ultimates.cooldowns.clear()
	rig.set_zoom(14.0)
	await _clear()


func _dummy(at: Vector3, hp := 2000.0, live := false) -> Enemy:
	var slime := (load(SLIME) as PackedScene).instantiate() as Enemy
	slime.simulate = live
	level.add_child(slime)
	slime.global_position = at
	slime.health.max_health = hp
	slime.health.reset()
	dummies.append(slime)
	return slime


func _clear() -> void:
	for dummy in dummies:
		if is_instance_valid(dummy):
			dummy.queue_free()
	dummies.clear()
	await _wait(5)


func _at(d: float, r: float = 0.0) -> Vector3:
	return ARENA + AIM * d + AIM.cross(Vector3.UP) * r


func _face() -> void:
	player.teleport_to(ARENA)
	await _wait(5)
	var visual := player.facing.visual_root if player.facing != null else null
	if visual != null:
		visual.rotation.y = FacingComponent.yaw_for_direction(AIM)
	rig.snap_to_target()
	await _wait(3)


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


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _seconds(seconds: float) -> void:
	if seconds > 0.0:
		await create_timer(seconds).timeout


func _expect(condition: bool, label: String) -> void:
	if not condition:
		problems.append(label)
		printerr("PROBLEM: ", label)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(file)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
