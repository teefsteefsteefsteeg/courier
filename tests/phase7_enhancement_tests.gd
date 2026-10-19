extends SceneTree
## Phase 7, Milestone C: armor and enhancement in the real village.
## - Defense: armor and shields lower the damage the courier takes (numbers at +0 and +5),
##   never below 1; the armor slot equips from the inventory window without touching the
##   hands.
## - Weapon enhancement raises sword, axe, bow and staff damage, and a real swing deals it.
## - Enhancing at Brenna: gold and iron ore are taken together or not at all, levels cap at
##   +5, tools and unowned items are not offered; levels and armor survive save and load.
## - Enhancement effects +1..+5 on the held weapon and around the body for armor; the
##   "Show enhancement effects" toggle hides them and keeps every bonus.
## - Attack timing: the swing pose, the swing arc and the hit land together; bolt and bow
##   poses are at their release when the projectile leaves; impact flashes on real hits.
##   godot --headless --path . --script res://tests/phase7_enhancement_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var wallet: CourierWallet
var combat: CombatController
var health: CombatHealth
var character: KayKitCharacter
var visuals: EnhancementVisuals
var attack_fx: AttackEffects
var shop: ShopUI
var equipment: EquipmentUI
var target: StaticBody3D
var target_health: CombatHealth
## Open ground by the Armory and a direction with nothing in the way for 6 m.
const ARENA := Vector3(5.6, 0, -11.0)
var aim: Vector3 = Vector3.BACK


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	UISettings.persist = false
	UISettings.set_value(UISettings.SHOW_ENHANCEMENT_VFX, true)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase7_enhancement_tests.json"
	root.add_child(level)
	# ShopUI attaches Brenna's Merchant to the current scene's Armory.
	current_scene = level
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	wallet = CourierWallet.find(self)
	combat = CombatController.find_on(player)
	health = combat.health
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	visuals = EnhancementVisuals.find(self)
	attack_fx = AttackEffects.find(self)
	shop = level.get_node("GameplayHUD/ShopUI") as ShopUI
	equipment = level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	await _frames(20)
	for id in [&"iron_sword", &"battle_axe", &"hunting_bow", &"magic_staff", &"wooden_shield", &"leather_vest", &"iron_mail", &"miner_pickaxe"]:
		inventory.add_item(inventory.get_definition(id))

	_check(visuals != null and attack_fx != null, "EnhancementVisuals and AttackEffects are level services")
	await _test_armor_slot()
	await _test_defense()
	await _test_weapon_damage()
	await _test_enhance_at_brenna()
	await _test_save_load()
	await _test_weapon_effects()
	await _test_armor_effects()
	await _test_toggle()
	await _test_melee_timing()
	await _test_projectile_timing()

	UISettings.reload()
	print("\n=== Phase 7 enhancement tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _unequip_all() -> void:
	for slot in [ItemDefinition.Slot.MAIN_HAND, ItemDefinition.Slot.OFF_HAND, ItemDefinition.Slot.ARMOR]:
		inventory.unequip(slot)


## Health the courier loses from one hit of amount (full health first).
func _damage_taken(amount: float) -> float:
	health.reset()
	var before := health.get_health()
	health.apply_damage(amount, player.global_position + Vector3.FORWARD)
	var lost := before - health.get_health()
	health.reset()
	return lost


func _spawn_target(offset: Vector3) -> void:
	if target != null and is_instance_valid(target):
		target.queue_free()
	target = StaticBody3D.new()
	target.name = "TrainingDummy"
	target.collision_layer = CombatController.ENEMY_LAYER
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	target.add_child(shape)
	target_health = CombatHealth.new()
	target_health.max_health = 1000.0
	target.add_child(target_health)
	level.add_child(target)
	target.global_position = player.global_position + offset
	await _physics(3)


func _wait_ready() -> void:
	for i in 300:
		if combat.is_magic_bolt_ready() and not combat.is_melee_pending():
			break
		await physics_frame


func _arena() -> void:
	player.teleport_to(ARENA)
	await _physics(6)
	var space := player.get_world_3d().direct_space_state
	for direction in [Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
		var from := player.global_position + Vector3.UP * combat.bolt_spawn_height
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * 6.0, combat.bolt_collision_mask, [player.get_rid()])
		if space.intersect_ray(query).is_empty():
			aim = direction
			return


# --- armor slot and defense --------------------------------------------------

func _test_armor_slot() -> void:
	print("[Armor slot]")
	_unequip_all()
	inventory.equip(&"iron_sword")
	await _frames(2)
	equipment.open()
	await _frames(2)
	equipment.activate_equip(&"leather_vest")
	await _frames(2)
	_check(inventory.get_equipped(ItemDefinition.Slot.ARMOR) == inventory.get_definition(&"leather_vest"), "the inventory window equips the Leather Vest in the armor slot")
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) == inventory.get_definition(&"iron_sword"), "wearing armor keeps the sword in hand")
	equipment.activate_equip(&"iron_mail")
	await _frames(2)
	_check(inventory.get_equipped(ItemDefinition.Slot.ARMOR) == inventory.get_definition(&"iron_mail") and not inventory.is_equipped(&"leather_vest"), "Iron Mail replaces the vest (one armor at a time)")
	_check(ItemDefinition.slot_name(ItemDefinition.Slot.ARMOR) == "Armor" and inventory.get_definition(&"iron_mail").get_stat_lines().has("+8 defense"), "armor is named and lists its defense")
	equipment.close()
	await _frames(3)


func _test_defense() -> void:
	print("[Defense lowers damage taken]")
	_unequip_all()
	await _frames(1)
	_check(is_zero_approx(combat.defense) and is_equal_approx(_damage_taken(10.0), 10.0), "no armor: a 10 damage hit takes 10")
	inventory.equip(&"leather_vest")
	_check(is_equal_approx(combat.defense, 4.0) and absf(_damage_taken(10.0) - 200.0 / 24.0) < 0.01, "Leather Vest +0 (defense 4): 10 -> %.2f" % _damage_taken(10.0))
	inventory.set_enhancement(&"leather_vest", 5)
	_check(is_equal_approx(combat.defense, 14.0) and absf(_damage_taken(10.0) - 200.0 / 34.0) < 0.01, "Leather Vest +5 (defense 14): 10 -> %.2f" % _damage_taken(10.0))
	inventory.equip(&"iron_mail")
	inventory.set_enhancement(&"iron_mail", 5)
	inventory.equip(&"wooden_shield")
	inventory.set_enhancement(&"wooden_shield", 5)
	_check(is_equal_approx(combat.defense, 30.0) and absf(_damage_taken(10.0) - 4.0) < 0.01, "Iron Mail +5 and Wooden Shield +5 (defense 30): 10 -> %.2f" % _damage_taken(10.0))
	_check(is_equal_approx(_damage_taken(1.0), 1.0), "a hit always deals at least 1")
	inventory.unequip(ItemDefinition.Slot.ARMOR)
	_check(is_equal_approx(combat.defense, 12.0), "taking the mail off leaves the shield's 12 defense (%.1f)" % combat.defense)
	inventory.unequip(ItemDefinition.Slot.OFF_HAND)
	_check(is_zero_approx(combat.defense) and is_equal_approx(_damage_taken(10.0), 10.0), "unequipping everything restores full damage")
	for id in [&"leather_vest", &"iron_mail", &"wooden_shield"]:
		inventory.set_enhancement(id, 0)


func _test_weapon_damage() -> void:
	print("[Weapon enhancement raises damage]")
	_unequip_all()
	var sword := inventory.get_definition(&"iron_sword")
	inventory.equip(&"iron_sword")
	_check(is_equal_approx(combat.melee_damage, sword.attack_damage), "Iron Sword +0 hits for %.0f" % combat.melee_damage)
	inventory.set_enhancement(&"iron_sword", 5)
	_check(is_equal_approx(combat.melee_damage, sword.attack_damage * 1.5), "Iron Sword +5 hits for %.0f (x1.5)" % combat.melee_damage)
	inventory.equip(&"battle_axe")
	inventory.set_enhancement(&"battle_axe", 2)
	_check(is_equal_approx(combat.melee_damage, inventory.get_definition(&"battle_axe").attack_damage * 1.2), "Battle Axe +2 hits for %.0f (x1.2)" % combat.melee_damage)
	inventory.equip(&"hunting_bow")
	inventory.set_enhancement(&"hunting_bow", 3)
	_check(is_equal_approx(combat.arrow_damage, inventory.get_definition(&"hunting_bow").attack_damage * 1.3), "Hunting Bow +3 arrows hit for %.1f (x1.3)" % combat.arrow_damage)
	var stats := level.get_node("GameplayServices/EquipmentStats") as EquipmentStats
	var bolt := stats.get_base_stat("bolt_damage") + inventory.get_definition(&"magic_staff").bolt_damage_bonus
	inventory.equip(&"magic_staff")
	_check(is_equal_approx(combat.bolt_damage, bolt), "Magic Staff +0 bolts hit for %.0f" % combat.bolt_damage)
	inventory.set_enhancement(&"magic_staff", 4)
	_check(is_equal_approx(combat.bolt_damage, bolt * 1.4), "Magic Staff +4 bolts hit for %.1f (x1.4)" % combat.bolt_damage)
	inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	_check(is_equal_approx(combat.bolt_damage, stats.get_base_stat("bolt_damage")), "bare hands: the staff's level no longer applies")
	# A real swing deals the enhanced damage.
	await _arena()
	inventory.equip(&"iron_sword")
	await _frames(2)
	await _spawn_target(aim * 1.2)
	await _wait_ready()
	var before := target_health.get_health()
	_check(combat.try_attack(aim), "the +5 sword swings")
	await _physics(20)
	_check(is_equal_approx(before - target_health.get_health(), sword.attack_damage * 1.5), "the swing took %.0f HP from the dummy" % (before - target_health.get_health()))
	for id in [&"iron_sword", &"battle_axe", &"hunting_bow", &"magic_staff"]:
		inventory.set_enhancement(id, 0)


# --- Brenna's enhancement service --------------------------------------------

func _test_enhance_at_brenna() -> void:
	print("[Enhancing at Brenna]")
	_unequip_all()
	inventory.equip(&"iron_sword")
	var armory := level.get_node("Armory") as Armory
	player.teleport_to(armory.get_shop_front().global_position)
	await _frames(5)
	await _press(&"interact")
	_check(shop.is_open() and shop.merchant != null and shop.merchant.get_catalog().enhances_items, "talking to Brenna opens the Armory with its Enhance section")
	_check(shop.enhance_rows.has(&"iron_sword") and shop.enhance_rows.has(&"iron_mail") and shop.enhance_rows.has(&"wooden_shield"), "owned weapons, shields and armor can be enhanced")
	_check(not shop.enhance_rows.has(&"miner_pickaxe"), "tools are not offered for enhancing")
	_check(shop.enhance_rows.has(&"steel_sword") and not (shop.enhance_rows[&"steel_sword"]["row"] as Control).visible, "an item the courier does not own is hidden")
	var ore := inventory.get_material_definition(Enhancement.ORE_ID)
	inventory.remove_materials({Enhancement.ORE_ID: inventory.get_material_count(Enhancement.ORE_ID)})
	wallet.restore(1000, wallet.reputation)
	await _frames(1)
	var button := shop.enhance_rows[&"iron_sword"]["button"] as Button
	shop.enhance_item(&"iron_sword")
	_check(button.disabled and wallet.gold == 1000 and inventory.get_enhancement(&"iron_sword") == 0, "no ore: the button is disabled and nothing is taken")
	inventory.add_material(ore, 1)
	wallet.restore(59, wallet.reputation)
	await _frames(1)
	var result := shop.enhance_item(&"iron_sword")
	_check(result == ShopService.EnhanceResult.NOT_ENOUGH_GOLD and wallet.gold == 59 and inventory.get_material_count(Enhancement.ORE_ID) == 1, "59 gold for a 60 gold step: refused, ore kept")
	wallet.restore(1000, wallet.reputation)
	await _frames(1)
	_check(not button.disabled, "with 60 gold and 1 ore the Enhance button is enabled")
	button.pressed.emit()
	_check(inventory.get_enhancement(&"iron_sword") == 1 and wallet.gold == 940 and inventory.get_material_count(Enhancement.ORE_ID) == 0, "+0 -> +1 costs 60 gold and 1 iron ore (gold %d)" % wallet.gold)
	_check(is_equal_approx(combat.melee_damage, inventory.get_definition(&"iron_sword").attack_damage * 1.1), "the equipped sword hits harder straight away")
	var gold := wallet.gold
	inventory.add_material(ore, 14)
	var spent_gold := 0
	var spent_ore := 0
	for step in range(1, Enhancement.MAX_LEVEL):
		spent_gold += Enhancement.gold_cost(step)
		spent_ore += Enhancement.ore_cost(step)
		shop.enhance_item(&"iron_sword")
	_check(inventory.get_enhancement(&"iron_sword") == 5 and wallet.gold == gold - spent_gold and inventory.get_material_count(Enhancement.ORE_ID) == 14 - spent_ore,
			"+1 -> +5 costs %d gold and %d ore in total (120+180+240+300, 2+3+4+5)" % [spent_gold, spent_ore])
	gold = wallet.gold
	var ore_left := inventory.get_material_count(Enhancement.ORE_ID)
	result = shop.enhance_item(&"iron_sword")
	_check(result == ShopService.EnhanceResult.MAX_LEVEL and wallet.gold == gold and inventory.get_material_count(Enhancement.ORE_ID) == ore_left and button.disabled and button.text == "Max",
			"+5 is the cap: refused, nothing taken, button shows Max")
	inventory.add_material(ore, 1)
	result = shop.enhance_item(&"iron_mail")
	_check(result == ShopService.EnhanceResult.OK and inventory.get_enhancement(&"iron_mail") == 1, "armor is enhanced the same way")
	shop.close()
	await _frames(3)


func _test_save_load() -> void:
	print("[Save and load]")
	_unequip_all()
	inventory.equip(&"iron_sword")
	inventory.equip(&"iron_mail")
	inventory.set_enhancement(&"iron_mail", 3)
	var data := inventory.to_dict()
	var defense := combat.defense
	inventory.from_dict({})
	await _frames(2)
	_check(is_zero_approx(combat.defense) and inventory.get_equipped(ItemDefinition.Slot.ARMOR) == null, "a cleared inventory has no armor or defense")
	inventory.from_dict(data)
	await _frames(3)
	_check(inventory.get_equipped(ItemDefinition.Slot.ARMOR) == inventory.get_definition(&"iron_mail") and inventory.get_enhancement(&"iron_mail") == 3 and inventory.get_enhancement(&"iron_sword") == 5,
			"armor slot and levels survive save and load")
	_check(is_equal_approx(combat.defense, defense) and is_equal_approx(combat.defense, 8.0 + 6.0), "defense is restored after loading (%.1f)" % combat.defense)
	_check(visuals.weapon_glow != null and visuals.weapon_glow.level == 5 and visuals.armor_aura != null, "the effects come back after loading")


# --- enhancement effects -----------------------------------------------------

func _test_weapon_effects() -> void:
	print("[Weapon effects +1..+5]")
	_unequip_all()
	inventory.equip(&"iron_sword")
	inventory.set_enhancement(&"iron_sword", 0)
	await _frames(3)
	_check(visuals.weapon_glow == null, "+0: no glow")
	# Phase 8 rework: each level is its own composition, not one glow in five colours.
	var signatures: Array[String] = []
	for lvl in range(1, Enhancement.MAX_LEVEL + 1):
		inventory.set_enhancement(&"iron_sword", lvl)
		await _frames(3)
		var glow := visuals.weapon_glow
		var ok := glow != null and is_instance_valid(glow) and glow.level == lvl and glow.get_parent() == character.get_held_item_node()
		_check(ok, "+%d %s: an effect on the held sword (%s)" % [lvl, EnhancementGlow.tier_name(ItemDefinition.WeaponType.SWORD, lvl), glow.elements if ok else []])
		if not ok:
			continue
		var sorted := glow.elements.duplicate()
		sorted.sort()
		signatures.append(",".join(sorted))
		var tip_distance := glow.tip.length() * EnhancementGlow._world_scale(character.get_held_item_node())
		_check(tip_distance > 0.4 and tip_distance < 2.0, "+%d: effects run along the blade (tip %.2f m from the grip)" % [lvl, tip_distance])
		if lvl == 5:
			_check(glow.elements.has(&"sword_inferno") and glow.elements.has(&"sword_fire_stream") and glow.elements.has(&"sword_ember_storm"), "+5: the inferno blade (flames, fire stream, ember storm)")
			var animated := glow.strips[0]
			var first := animated.frame
			await create_timer(0.25).timeout
			_check(animated.frame != first, "+5: the flames animate")
			_check(glow.light != null and glow.light.light_color.r > glow.light.light_color.b, "+5: a warm fire light")
	var unique := {}
	for signature in signatures:
		unique[signature] = true
	_check(signatures.size() == 5 and unique.size() == 5, "five different effect sets %s" % [signatures])
	inventory.equip(&"miner_pickaxe")
	await _frames(3)
	_check(visuals.weapon_glow == null, "a tool in hand shows no glow (the sword's level stays %d)" % inventory.get_enhancement(&"iron_sword"))
	inventory.equip(&"wooden_shield")
	inventory.set_enhancement(&"wooden_shield", 2)
	await _frames(3)
	_check(visuals.shield_glow != null and visuals.shield_glow.get_parent() == character.get_off_hand_item_node(), "an enhanced shield glows in the left hand")
	inventory.set_enhancement(&"wooden_shield", 0)
	inventory.equip(&"iron_sword")
	await _frames(3)


func _test_armor_effects() -> void:
	print("[Armor effects +1..+5]")
	inventory.equip(&"leather_vest")
	inventory.set_enhancement(&"leather_vest", 0)
	await _frames(3)
	_check(visuals.armor_aura == null, "+0 armor: no aura")
	var amounts: Array[int] = []
	for lvl in range(1, Enhancement.MAX_LEVEL + 1):
		inventory.set_enhancement(&"leather_vest", lvl)
		# The effect's "open" animation starts its particles after 0.1 s.
		await create_timer(0.2).timeout
		var aura := visuals.armor_aura
		var particles := visuals.get_armor_particles()
		var ok := aura != null and aura.get_parent() == player and particles != null and particles.emitting
		_check(ok, "+%d: an aura emits around the courier" % lvl)
		if not ok:
			continue
		amounts.append(particles.amount)
		var color: Color = aura.get(&"primary_color")
		_check(color.is_equal_approx(Enhancement.level_color(lvl)) and (particles.material_override as ShaderMaterial).get_shader_parameter(&"primary_color") == color, "+%d: aura in the level colour" % lvl)
		var streaks := aura.get_node(^"MeshInstance3D") as MeshInstance3D
		_check(streaks.visible == (lvl == 5), "+%d: light streaks only at +5" % lvl)
		_check(absf(aura.position.y - EnhancementVisuals.AURA_HEIGHT) < 0.01, "+%d: centred on the body" % lvl)
	_check(amounts.size() == 5 and amounts[0] < amounts[2] and amounts[2] < amounts[4], "more particles at higher levels %s" % [amounts])
	var old := visuals.armor_aura
	player.teleport_to(player.global_position + Vector3(2, 0, 0))
	await _frames(3)
	_check(visuals.armor_aura == old and old.get_parent() == player, "the aura follows a teleport")
	inventory.unequip(ItemDefinition.Slot.ARMOR)
	await _frames(3)
	_check(visuals.armor_aura == null and not is_instance_valid(old) or (old != null and old.is_queued_for_deletion()), "taking the armor off removes the aura")
	inventory.equip(&"leather_vest")
	await _frames(3)


func _test_toggle() -> void:
	print("[Show enhancement effects toggle]")
	inventory.equip(&"iron_sword")
	inventory.set_enhancement(&"iron_sword", 5)
	inventory.set_enhancement(&"leather_vest", 5)
	await _frames(3)
	var damage := combat.melee_damage
	var defense := combat.defense
	_check(visuals.weapon_glow != null and visuals.armor_aura != null, "effects show by default")
	equipment.open()
	await _frames(2)
	_check(equipment.vfx_toggle != null and equipment.vfx_toggle.button_pressed and equipment.vfx_toggle.is_visible_in_tree(), "the inventory footer has 'Show enhancement effects', on")
	equipment.vfx_toggle.button_pressed = false
	await _frames(3)
	_check(not UISettings.show_enhancement_vfx(), "unticking it changes the setting")
	_check(visuals.weapon_glow == null and visuals.armor_aura == null, "effects hidden")
	_check(player.find_children("EnhancementGlow", "", true, false).is_empty() and player.find_children("EnhancementArmorAura", "", true, false).is_empty(), "nothing left on the courier")
	_check(is_equal_approx(combat.melee_damage, damage) and is_equal_approx(combat.defense, defense) and absf(_damage_taken(10.0) - 200.0 / (20.0 + defense)) < 0.01,
			"hidden effects keep the bonuses (damage %.0f, defense %.0f)" % [combat.melee_damage, combat.defense])
	equipment.close()
	await _frames(3)
	inventory.set_enhancement(&"iron_sword", 4)
	await _frames(3)
	_check(visuals.weapon_glow == null, "levelling up while hidden stays hidden")
	equipment.open()
	await _frames(2)
	_check(not equipment.vfx_toggle.button_pressed, "the toggle reopens unticked")
	equipment.vfx_toggle.button_pressed = true
	await _frames(3)
	_check(visuals.weapon_glow != null and visuals.weapon_glow.level == 4 and visuals.armor_aura != null, "ticking it shows the effects again")
	equipment.close()
	await _frames(3)


# --- attack timing -----------------------------------------------------------

func _test_melee_timing() -> void:
	print("[Melee: pose, arc and hit together]")
	await _arena()
	for weapon_id in [&"iron_sword", &"battle_axe"]:
		inventory.equip(weapon_id)
		await _frames(3)
		await _spawn_target(aim * 1.2)
		await _wait_ready()
		var spawned: Array = []
		var on_spawn := func(kind: StringName, effect: Node3D) -> void: spawned.append([kind, effect])
		attack_fx.effect_spawned.connect(on_spawn)
		var hit_strike := [INF, INF]
		var on_resolved := func(_hits: int) -> void:
			hit_strike[0] = character.get_strike_remaining()
			var anim := (attack_fx.swing.get_node(^"AnimationPlayer") as AnimationPlayer) if attack_fx.swing != null and is_instance_valid(attack_fx.swing) else null
			hit_strike[1] = anim.current_animation_position if anim != null else INF
		combat.melee_resolved.connect(on_resolved)
		var before := target_health.get_health()
		combat.try_attack(aim)
		var name := inventory.get_definition(weapon_id).display_name
		var strike_in := character.get_strike_remaining()
		_check(absf(strike_in - combat.melee_windup) < 0.02, "%s: the swing pose strikes in %.3f s, the hit lands in %.3f s" % [name, strike_in, combat.melee_windup])
		_check(attack_fx.swing != null and absf(float(attack_fx.swing.get(&"speed_scale")) * combat.melee_windup - AttackEffects.SWING_PEAK) < 0.001, "%s: the swing arc peaks at the hit" % name)
		var arc_basis := attack_fx.swing.global_basis.orthonormalized() if attack_fx.swing != null else Basis()
		_check(arc_basis.x.dot(aim) > 0.99, "%s: the arc opens towards the swing" % name)
		_check((absf(arc_basis.y.dot(Vector3.UP)) > 0.99) == (weapon_id == &"iron_sword"), "%s: %s" % [name, "a level cut" if weapon_id == &"iron_sword" else "a vertical chop"])
		for i in 90:
			await process_frame
			if hit_strike[0] != INF:
				break
		await _physics(3)
		# One frame (~1/60 s, faster on a fast machine) of tolerance at the measured moment.
		_check(absf(hit_strike[0]) < 0.04, "%s: when the hit lands the pose is %.3f s from its strike" % [name, hit_strike[0]])
		_check(absf(hit_strike[1] - AttackEffects.SWING_PEAK) < 0.04 * float(attack_fx.swing.get(&"speed_scale") if attack_fx.swing != null and is_instance_valid(attack_fx.swing) else 1.0) + 0.02,
				"%s: the arc is at %.3f of its %.2f s peak when the hit lands" % [name, hit_strike[1], AttackEffects.SWING_PEAK])
		_check(target_health.get_health() < before, "%s: the dummy took the hit" % name)
		var impacts := spawned.filter(func(e: Array) -> bool: return e[0] == &"impact")
		_check(impacts.size() == 1 and (impacts[0][1] as Node3D).global_position.distance_to(target.global_position - aim * AttackEffects.IMPACT_SURFACE + Vector3.UP * AttackEffects.IMPACT_HEIGHT) < 0.05,
				"%s: one impact flash on the dummy's near side" % name)
		attack_fx.effect_spawned.disconnect(on_spawn)
		combat.melee_resolved.disconnect(on_resolved)
		await create_timer(0.7).timeout
		_check(level.find_children("ImpactFlash", "", true, false).is_empty(), "%s: the flash removes itself" % name)
	# A swing cancelled by a weapon switch takes its arc with it.
	inventory.equip(&"battle_axe")
	await _wait_ready()
	combat.try_attack(aim)
	var arc := attack_fx.swing
	var had_arc := arc != null
	inventory.equip(&"iron_sword")
	await _frames(2)
	_check(had_arc and not is_instance_valid(arc) and attack_fx.swing == null, "switching weapons mid-swing removes the arc")


func _test_projectile_timing() -> void:
	print("[Bow and bolt: release pose when the projectile leaves]")
	await _arena()
	inventory.equip(&"hunting_bow")
	await _frames(3)
	await _spawn_target(aim * 4.0)
	await _wait_ready()
	var spawned: Array = []
	var on_spawn := func(kind: StringName, effect: Node3D) -> void: spawned.append(kind)
	attack_fx.effect_spawned.connect(on_spawn)
	var before := target_health.get_health()
	combat.try_attack(aim)
	_check(character.one_shot_action == &"shoot" and absf(character.get_strike_remaining()) < 0.01, "bow: the pull is at its release as the arrow leaves (%.3f s)" % character.get_strike_remaining())
	for i in 120:
		await physics_frame
		if target_health.get_health() < before:
			break
	await _frames(2)
	_check(target_health.get_health() < before and spawned.has(&"impact"), "bow: the arrow hits and flashes on impact")
	spawned.clear()
	inventory.equip(&"magic_staff")
	await _frames(3)
	await _wait_ready()
	before = target_health.get_health()
	combat.try_attack(aim)
	_check(character.one_shot_action == &"attack" and absf(character.get_strike_remaining()) < 0.01, "staff: the cast is at its throw as the bolt leaves")
	for i in 120:
		await physics_frame
		if target_health.get_health() < before:
			break
	await _frames(2)
	_check(target_health.get_health() < before and not spawned.has(&"impact"), "staff: the bolt hits with its own burst (no extra flash)")
	attack_fx.effect_spawned.disconnect(on_spawn)
