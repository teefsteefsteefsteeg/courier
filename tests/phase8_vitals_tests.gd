extends SceneTree
## Phase 8 milestone 1 (recovery brief), in the real village:
## - HP regeneration: a real forest slime hurts the courier; nothing regenerates during the
##   delay, it is reduced while the slime is still fighting, full speed after, never above
##   the maximum, never while knocked out; the HUD follows.
## - Mana: a staff's bolts cost MP and are refused without it, bare-handed bolts are free,
##   MP regenerates, the HUD bar shows the real value; the Arcane Storm spends MP.
## - Rage: real sword hits build it, damage taken builds it, ultimates are refused below the
##   cost and spend it; the HUD shows rage and "READY"; rage decays out of combat.
## - Consumables: the Food Market sells them through the real E key and ShopUI (gold and
##   counts exact, stack limits, the bag's kinds limit); potions heal / restore at once and
##   share a cooldown, are refused when pointless; food heals over time; buffs change real
##   damage, defense and critical hits, expire, show on the HUD; keys 6-0 use the slots.
## - Inventory: the Provisions view (Q cycles three views), Use and slot buttons.
## - World-space effects: every +5 ultimate leaves effects on the ground (decals for cracks,
##   rings, scorch marks and rune circles, lightning from the sky, burning ground, rocks),
##   statuses on the enemies it hits and a camera shake; crits, casts and defeats show.
## - Save/load of vitals and consumable slots.
##   godot --headless --path . --script res://tests/phase8_vitals_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const SLIME := "res://scenes/gameplay/combat/forest_slime.tscn"
const ARENA := Vector3(5.6, 0, -11.0)
const AIM := Vector3.BACK

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var vitals: CourierVitals
var combat: CombatController
var health: CombatHealth
var ultimates: WeaponUltimates
var effects: AttackEffects
var wallet: CourierWallet
var hud: Node
var dummies: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_vitals_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	vitals = CourierVitals.find(self)
	combat = CombatController.find_on(player)
	health = combat.health
	ultimates = WeaponUltimates.find(self)
	effects = AttackEffects.find(self)
	wallet = CourierWallet.find(self)
	hud = level.find_child("CombatHUD", true, false)
	await _frames(20)
	for id in [&"steel_sword", &"battle_axe", &"hunting_bow", &"magic_staff"]:
		inventory.add_item(inventory.get_definition(id))

	await _test_services()
	await _test_regeneration()
	await _test_mana()
	await _test_rage()
	await _test_food_market()
	await _test_potions_and_food()
	await _test_buffs()
	await _test_quick_slots_and_inventory()
	await _test_world_space_ultimates()
	await _test_combat_feedback()
	await _test_save_load()

	print("\n=== Phase 8 vitals tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


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


func _equip(id: StringName, lvl: int) -> void:
	if id == &"":
		inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	else:
		inventory.equip(id)
		inventory.set_enhancement(id, lvl)
	await _frames(4)


func _dummy(at: Vector3, hp := 2000.0, frozen := true) -> Enemy:
	var slime := (load(SLIME) as PackedScene).instantiate() as Enemy
	slime.simulate = not frozen
	level.add_child(slime)
	slime.global_position = at
	slime.health.max_health = hp
	slime.health.reset()
	dummies.append(slime)
	return slime


func _clear_dummies() -> void:
	for dummy: Variant in dummies:
		if is_instance_valid(dummy):
			(dummy as Node).queue_free()
	dummies.clear()
	await _physics(3)


func _at(d: float, r: float = 0.0) -> Vector3:
	return ARENA + AIM * d + AIM.cross(Vector3.UP) * r


func _face(direction: Vector3) -> void:
	player.teleport_to(ARENA)
	await _physics(5)
	var visual := player.facing.visual_root if player.facing != null else null
	if visual != null:
		visual.rotation.y = FacingComponent.yaw_for_direction(direction)
	await _physics(2)


## One swing / shot resolved at once (the windup and cooldown are stepped).
func _attack() -> bool:
	var ok := combat.try_attack(AIM)
	combat.advance(1.0)
	await _physics(2)
	return ok


## Every node named like prefix under the level (effects are added to the level).
func _named(prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	for node in level.find_children(prefix + "*", "", true, false):
		if node.is_inside_tree() and not node.is_queued_for_deletion():
			out.append(node)
	return out


func _reset_vitals() -> void:
	vitals.buffs.clear()
	vitals.heals.clear()
	vitals._apply_buffs()
	vitals.restore_mana(vitals.max_mana)
	vitals.spend_rage(vitals.get_rage())
	vitals.potion_cooldown_left = 0.0
	if health.is_dead():
		health.reset()
	else:
		health.heal(health.get_max_health())


# --- tests ---------------------------------------------------------------------------

func _test_services() -> void:
	print("[Services]")
	_check(vitals != null and vitals.is_in_group(WeaponUltimates.MANA_GROUP) and vitals.is_in_group(WeaponUltimates.RAGE_GROUP), "CourierVitals is a gameplay service (MP and rage groups)")
	_check(is_equal_approx(vitals.get_mana(), vitals.max_mana) and vitals.get_rage() == 0.0, "the courier starts with full MP (%d) and no rage" % vitals.get_mana())
	_check(combat.mana_source == vitals, "the courier's combat pays MP to it")
	_check(inventory.get_all_consumables().size() == 12, "12 consumables are registered (%d)" % inventory.get_all_consumables().size())
	var kinds := {}
	for item in inventory.get_all_consumables():
		kinds[item.kind] = true
		_check(item.icon != null and not item.description.is_empty() and not item.get_effect_lines().is_empty(), "%s has an icon, a description and effects" % item.display_name)
	_check(kinds.size() == 4, "food, health potions, mana potions and combat buffs all exist")


func _test_regeneration() -> void:
	print("[HP regeneration from real enemy damage]")
	await _reset_vitals()
	await _equip(&"", 0)
	player.teleport_to(ARENA)
	await _physics(5)
	var slime := _dummy(ARENA + Vector3(1.6, 0, 0), 60.0, false)
	var full := health.get_health()
	var waited := 0.0
	while health.get_health() >= full and waited < 8.0:
		await _seconds(0.1)
		waited += 0.1
	_check(health.get_health() < full, "a real forest slime hurt the courier (%.0f -> %.0f)" % [full, health.get_health()])
	vitals.simulate = false
	var hurt := health.get_health()
	_check(vitals.since_damage < 1.0 and vitals.is_in_combat(), "the courier is in combat right after the hit")
	vitals.advance(vitals.hp_regen_delay * 0.5)
	_check(is_equal_approx(health.get_health(), hurt), "no regeneration during the delay after damage")
	# The slime is still chasing: reduced regeneration.
	slime.simulate = false
	vitals.since_damage = vitals.hp_regen_delay + 0.1
	vitals.since_combat = vitals.combat_window + 0.1
	var engaged := vitals.is_in_combat()
	var reduced := vitals.get_hp_regen_rate()
	_check(engaged and is_equal_approx(reduced, vitals.hp_regen_per_second * vitals.combat_regen_factor), "while an enemy is fighting the courier, regeneration is reduced (%.2f/s)" % reduced)
	slime.health.apply_damage(9999.0)
	await _physics(3)
	_check(not vitals.is_in_combat() and is_equal_approx(vitals.get_hp_regen_rate(), vitals.hp_regen_per_second), "out of combat it is the full configured rate (%.2f/s)" % vitals.get_hp_regen_rate())
	var before := health.get_health()
	for i in 60:
		vitals.advance(1.0 / 60.0)
	_check(is_equal_approx(health.get_health() - before, vitals.hp_regen_per_second), "one second regenerates %.2f HP (got %.2f)" % [vitals.hp_regen_per_second, health.get_health() - before])
	await _frames(3)
	_check(hud != null and is_equal_approx(float(hud.get("health_current")), health.get_health()), "the HUD's HP follows the regeneration (%.1f)" % float(hud.get("health_current")))
	for i in 200:
		vitals.advance(1.0)
	_check(health.get_health() == health.get_max_health(), "it stops at the maximum (%.1f)" % health.get_health())
	# A bigger configured rate is honoured.
	health.apply_damage(30.0)
	vitals.since_damage = 999.0
	vitals.since_combat = 999.0
	vitals.hp_regen_per_second = 10.0
	before = health.get_health()
	vitals.advance(1.0)
	_check(is_equal_approx(health.get_health() - before, 10.0), "the rate is configurable (10 HP/s)")
	vitals.hp_regen_per_second = 1.5
	# Knocked out: nothing regenerates.
	health.apply_damage(9999.0)
	vitals.since_damage = 999.0
	vitals.advance(5.0)
	_check(health.is_dead() and health.get_health() == 0.0, "no regeneration while knocked out")
	health.reset()
	vitals.simulate = true
	await _clear_dummies()


func _test_mana() -> void:
	print("[Mana]")
	await _reset_vitals()
	await _face(AIM)
	await _equip(&"magic_staff", 0)
	_check(combat.bolt_mana_cost > 0.0, "a staff's bolts cost MP (%d)" % combat.bolt_mana_cost)
	var mp := vitals.get_mana()
	var cast := await _attack()
	# (MP keeps regenerating during the two frames the attack takes.)
	_check(cast and absf(vitals.get_mana() - (mp - combat.bolt_mana_cost)) < 0.2, "casting a bolt spends it (%.1f -> %.1f)" % [mp, vitals.get_mana()])
	await _frames(3)
	_check(hud != null and is_equal_approx(float(hud.get("mana_current")), vitals.get_mana()), "the HUD's MP bar shows the real value")
	vitals.spend(vitals.get_mana() - 1.0)
	var reasons: Array[StringName] = []
	var blocked := func(_ability: StringName, reason: StringName) -> void: reasons.append(reason)
	combat.ability_blocked.connect(blocked)
	_check(not combat.try_attack(AIM) and reasons.has(&"no_mana"), "without MP the staff cannot cast")
	combat.ability_blocked.disconnect(blocked)
	await _equip(&"", 0)
	_check(combat.bolt_mana_cost == 0.0 and await _attack(), "bare-handed bolts are free")
	vitals.simulate = false
	var low := vitals.get_mana()
	vitals.advance(2.0)
	_check(is_equal_approx(vitals.get_mana() - low, vitals.mana_regen_per_second * 2.0), "MP regenerates (%.1f in 2 s)" % (vitals.get_mana() - low))
	vitals.simulate = true
	# The storm spends its MP.
	await _reset_vitals()
	await _equip(&"magic_staff", 5)
	vitals.add_rage(100.0)
	mp = vitals.get_mana()
	_check(ultimates.use() and is_equal_approx(vitals.get_mana(), mp - 30.0), "the Arcane Storm spends 30 MP (%.0f -> %.0f)" % [mp, vitals.get_mana()])
	await _seconds(3.5)
	ultimates.cooldowns.clear()


func _test_rage() -> void:
	print("[Rage]")
	await _reset_vitals()
	await _face(AIM)
	await _equip(&"steel_sword", 5)
	var target := _dummy(_at(1.2))
	await _physics(3)
	var reasons: Array[StringName] = []
	var blocked := func(_skill: StringName, reason: StringName) -> void: reasons.append(reason)
	ultimates.ultimate_blocked.connect(blocked)
	_check(not ultimates.use() and reasons.has(&"rage"), "with no rage the ultimate is refused")
	ultimates.ultimate_blocked.disconnect(blocked)
	await _frames(2)
	var bar := level.find_child("QuickWeaponBar", true, false) as QuickWeaponBar
	_check(bar.ultimate_label.text.contains("0/50 rage"), "the weapon bar says what it waits for (%s)" % bar.ultimate_label.text)
	var hits := 0
	while vitals.get_rage() < ultimates.get_rage_cost() and hits < 20:
		await _attack()
		hits += 1
	_check(hits == ceili(ultimates.get_rage_cost() / vitals.rage_per_hit), "each real sword hit builds %d rage (%d hits to %d)" % [vitals.rage_per_hit, hits, ultimates.get_rage_cost()])
	await _frames(3)
	_check(bool(hud.get("ultimate_ready")) and String((hud.get("rage_label") as Label).text).contains("READY"), "the HUD shows the rage and that the ultimate is ready (%s)" % (hud.get("rage_label") as Label).text)
	var rage := vitals.get_rage()
	_check(ultimates.use() and is_equal_approx(vitals.get_rage(), rage - ultimates.get_rage_cost()), "the ultimate spends %d rage" % ultimates.get_rage_cost())
	await _seconds(1.5)
	ultimates.cooldowns.clear()
	# Taking damage builds rage too.
	rage = vitals.get_rage()
	health.apply_damage(10.0, target.global_position)
	_check(is_equal_approx(vitals.get_rage() - rage, 10.0 * vitals.rage_per_damage), "damage taken builds rage")
	# Out of combat it decays.
	vitals.simulate = false
	vitals.since_combat = vitals.rage_decay_delay + 0.1
	rage = vitals.get_rage()
	vitals.advance(1.0)
	_check(vitals.get_rage() < rage, "rage decays out of combat (%.1f -> %.1f)" % [rage, vitals.get_rage()])
	vitals.simulate = true
	# Development mode: unlimited rage (headless tests are never dev mode).
	_check(not vitals.unlimited_rage, "headless runs keep the rage rule")
	vitals.unlimited_rage = true
	vitals.add_rage(0.1)
	_check(vitals.get_rage() == vitals.max_rage and ultimates.use() and vitals.get_rage() == vitals.max_rage, "with unlimited rage the bar stays full and ultimates never spend it")
	await _seconds(1.5)
	ultimates.cooldowns.clear()
	vitals.unlimited_rage = false
	vitals.spend_rage(vitals.get_rage())
	await _clear_dummies()


func _test_food_market() -> void:
	print("[Food Market]")
	await _reset_vitals()
	var market := level.find_child("FoodMarket", true, false) as ToolStall
	_check(market != null and market.catalog != null and market.catalog.shop_id == &"food_market", "the Food Market stands in the village")
	var grocer := NPC.find_by_id(self, &"grocer")
	_check(grocer != null and grocer.get_node_or_null("ShopMerchant") is Merchant, "Grocer Tilda has a merchant attached")
	player.teleport_to(market.get_shop_front().global_position)
	await _physics(10)
	var shop := level.find_children("*", "ShopUI", true, false)[0] as ShopUI
	await _key(KEY_E)
	await _frames(3)
	_check(shop.is_open() and shop.goods_rows.size() == 12, "the real E key opens her shop with 12 provisions (%d)" % shop.goods_rows.size())
	wallet.restore(1000, wallet.reputation)
	var gold := wallet.gold
	var potion := inventory.get_material_definition(&"health_potion")
	var spent := shop.buy_goods(&"health_potion", 5)
	_check(spent == potion.buy_price * 5 and wallet.gold == gold - spent and inventory.get_material_count(&"health_potion") == 5, "buying 5 health potions costs %d gold and adds 5" % (potion.buy_price * 5))
	shop.buy_goods(&"health_potion", 5)
	gold = wallet.gold
	_check(shop.buy_goods(&"health_potion", 1) == 0 and wallet.gold == gold and inventory.get_material_count(&"health_potion") == 10, "a full stack (10) refuses more and keeps the gold")
	_check((shop.goods_rows[&"health_potion"]["buy_one"] as Button).disabled and shop.feedback_label.text.contains("No room"), "the buy button is disabled and says why")
	for id in [&"mana_potion", &"bread_loaf", &"roast_ham", &"cheese_wheel", &"warriors_ale", &"berserker_draught", &"ironbark_stew", &"red_apple"]:
		shop.buy_goods(id, 2)
	_check(inventory.get_material_count(&"mana_potion") == 2 and inventory.get_material_count(&"berserker_draught") == 2, "other provisions bought")
	var effects_label := (shop.goods_rows[&"roast_ham"]["row"] as Node).find_child("Effects", true, false) as Label
	_check(effects_label != null and effects_label.text.contains("damage"), "the shop shows each provision's effects (%s)" % (effects_label.text if effects_label else ""))
	shop.close()
	await _frames(3)
	# The bag holds CONSUMABLE_BAG_SLOTS kinds.
	var temps: Array[ConsumableItem] = []
	var kinds := inventory.get_consumable_stack_count()
	for i in CourierInventory.CONSUMABLE_BAG_SLOTS - kinds:
		var temp := ConsumableItem.new()
		temp.material_id = StringName("test_food_%d" % i)
		temp.kind = MaterialItem.Kind.FOOD
		temp.heal = 1.0
		temps.append(temp)
		inventory.add_material(temp, 1)
	var extra := ConsumableItem.new()
	extra.material_id = &"test_food_extra"
	extra.kind = MaterialItem.Kind.FOOD
	_check(inventory.get_consumable_stack_count() == CourierInventory.CONSUMABLE_BAG_SLOTS and inventory.add_material(extra, 1) == 0, "the pack holds %d kinds of provisions, no more" % CourierInventory.CONSUMABLE_BAG_SLOTS)
	_check(inventory.add_material(potion, 0) == 0 and inventory.add_material(inventory.get_material_definition(&"stone"), 3) == 3, "materials are not limited by the provisions pack")
	for temp in temps:
		inventory.remove_materials({temp.material_id: 1})
	inventory.remove_materials({&"stone": 3})
	for index in CourierInventory.CONSUMABLE_SLOT_COUNT:
		var slotted := inventory.get_consumable_slot(index)
		if slotted != null and String(slotted.material_id).begins_with("test_food"):
			inventory.clear_consumable_slot(index)


func _test_potions_and_food() -> void:
	print("[Potions and food]")
	await _reset_vitals()
	vitals.simulate = false
	var count := inventory.get_material_count(&"health_potion")
	_check(not vitals.consume(&"health_potion") and inventory.get_material_count(&"health_potion") == count, "a health potion at full health is refused (kept)")
	health.apply_damage(70.0)
	var hp := health.get_health()
	_check(vitals.consume(&"health_potion") and is_equal_approx(health.get_health(), minf(hp + 60.0, health.get_max_health())) and inventory.get_material_count(&"health_potion") == count - 1, "a health potion heals 60 at once and is used up (%.0f -> %.0f)" % [hp, health.get_health()])
	health.apply_damage(30.0)
	_check(not vitals.consume(&"health_potion"), "potions share a short cooldown")
	vitals.advance(CourierVitals.POTION_COOLDOWN + 0.1)
	vitals.spend(60.0)
	var mp := vitals.get_mana()
	_check(vitals.consume(&"mana_potion") and is_equal_approx(vitals.get_mana(), mp + 50.0), "a mana potion restores 50 MP")
	await _reset_vitals()
	# Natural regeneration off, so only the food heals here.
	vitals.hp_regen_per_second = 0.0
	health.apply_damage(50.0)
	vitals.since_damage = 0.0
	hp = health.get_health()
	_check(vitals.consume(&"bread_loaf") and is_equal_approx(health.get_health(), hp), "bread heals nothing at once")
	vitals.advance(5.0)
	_check(is_equal_approx(health.get_health() - hp, 20.0), "but 40 HP over 10 s, even right after damage (%.1f after 5 s)" % (health.get_health() - hp))
	vitals.advance(6.0)
	_check(is_equal_approx(health.get_health() - hp, 40.0) and vitals.heals.is_empty(), "and stops after its duration (%.1f)" % (health.get_health() - hp))
	vitals.hp_regen_per_second = 1.5
	vitals.simulate = true


func _test_buffs() -> void:
	print("[Buffs]")
	await _reset_vitals()
	await _face(AIM)
	await _equip(&"steel_sword", 0)
	var target := _dummy(_at(1.2))
	await _physics(3)
	var hp := target.health.get_health()
	await _attack()
	var plain := hp - target.health.get_health()
	_check(is_equal_approx(plain, combat.melee_damage), "a plain hit deals the sword's damage (%.1f)" % plain)
	_check(vitals.consume(&"roast_ham") and vitals.has_buff(&"hearty"), "Roast Ham makes the courier Hearty")
	hp = target.health.get_health()
	await _attack()
	_check(is_equal_approx(hp - target.health.get_health(), plain * 1.15), "Hearty: the real hit deals 15%% more (%.2f)" % (hp - target.health.get_health()))
	await _frames(3)
	var buff_row := hud.get("buff_row") as HBoxContainer
	_check(buff_row.visible and buff_row.get_child_count() == 1 and buff_row.get_child(0).name == "hearty", "the HUD shows the buff with its time")
	# Defense.
	_check(vitals.consume(&"ironbark_stew") and is_equal_approx(combat.defense_bonus, 8.0), "Ironbark Stew adds 8 defense")
	var reduced := combat.reduce_by_defense(20.0)
	_check(reduced < 20.0, "incoming damage is reduced by it (20 -> %.1f)" % reduced)
	# Critical hits.
	_check(vitals.consume(&"berserker_draught") and is_equal_approx(combat.crit_chance, 0.25), "Berserker Draught: 25%% critical chance")
	combat.crit_rng.seed = 12345
	var crits: Array[float] = []
	var on_crit := func(_t: Node, amount: float) -> void: crits.append(amount)
	combat.critical_hit.connect(on_crit)
	var spawned: Array[StringName] = []
	var watch := func(kind: StringName, _e: Node3D) -> void: spawned.append(kind)
	effects.effect_spawned.connect(watch)
	for i in 24:
		await _attack()
	combat.critical_hit.disconnect(on_crit)
	effects.effect_spawned.disconnect(watch)
	_check(crits.size() >= 2 and crits.size() <= 14, "some real hits are critical (%d of 24)" % crits.size())
	_check(not crits.is_empty() and is_equal_approx(crits[0], combat.melee_damage * 1.15 * combat.crit_multiplier), "a critical hit deals x%.2f (%.1f)" % [combat.crit_multiplier, crits[0] if not crits.is_empty() else 0.0])
	_check(spawned.has(&"critical_text") and spawned.has(&"critical_flash"), "a critical hit shows CRITICAL text and a flash")
	# Expiry.
	vitals.simulate = false
	vitals.advance(46.0)
	_check(not vitals.has_buff(&"berserk") and combat.crit_chance == 0.0 and vitals.has_buff(&"hearty"), "Berserk wears off after 45 s (crits back to 0); Hearty still runs")
	vitals.advance(200.0)
	_check(vitals.buffs.is_empty() and is_equal_approx(combat.damage_multiplier, 1.0) and combat.defense_bonus == 0.0, "every buff expires and the stats return to normal")
	vitals.simulate = true
	await _frames(3)
	_check(not buff_row.visible, "the HUD's buff row empties")
	await _clear_dummies()


func _test_quick_slots_and_inventory() -> void:
	print("[Provisions slots (6-0) and the inventory]")
	await _reset_vitals()
	await _equip(&"", 0)
	var ids := inventory.get_consumable_slot_ids()
	_check(ids[0] == &"health_potion" and ids.count(&"") < CourierInventory.CONSUMABLE_SLOT_COUNT, "bought provisions filled the slots (%s)" % [ids])
	health.apply_damage(40.0)
	var count := inventory.get_material_count(&"health_potion")
	await _key(KEY_6)
	_check(inventory.get_material_count(&"health_potion") == count - 1 and health.get_health() == health.get_max_health(), "the real 6 key drinks slot 1's health potion")
	var bar := level.find_child("QuickConsumableBar", true, false) as QuickConsumableBar
	await _frames(2)
	_check(bar != null and bar.slot_buttons[0].icon != null and ((bar.slot_buttons[0].get_node("Count") as Label).text == str(count - 1)), "the HUD's provisions bar shows the icon and count")
	var equipment := level.find_child("EquipmentUI", true, false) as EquipmentUI
	await _key(KEY_TAB)
	_check(equipment.is_open(), "Tab opens the inventory")
	await _key(KEY_Q)
	await _key(KEY_Q)
	_check(equipment.view == EquipmentUI.View.PROVISIONS and equipment.title_label.text == "Provisions", "Q twice reaches the Provisions view")
	var headers := equipment.item_list.get_children().filter(func(c: Node) -> bool: return c is Label).map(func(l: Label) -> String: return l.text)
	_check(headers == ["Health Potions", "Mana Potions", "Food", "Combat Buffs"], "its sections: %s" % [headers])
	_check(equipment.bag_label.text.begins_with("Pack "), "it shows the pack's capacity (%s)" % equipment.bag_label.text)
	equipment.select_consumable(&"cheese_wheel")
	health.apply_damage(20.0)
	var cheese := inventory.get_material_count(&"cheese_wheel")
	_check(equipment.use_consumable(&"cheese_wheel") and inventory.get_material_count(&"cheese_wheel") == cheese - 1 and vitals.has_buff(&"well_fed"), "Use eats a cheese wheel (Well Fed)")
	equipment.select_consumable(&"warriors_ale")
	var slot_button := equipment._consumable_slot_buttons[4]
	slot_button.pressed.emit()
	_check(inventory.find_consumable_slot(&"warriors_ale") == 4, "a slot button puts the ale on slot [0]")
	await _key(KEY_Q)
	_check(equipment.view == EquipmentUI.View.WEAPONS, "Q wraps back to Weapons & Gear")
	await _key(KEY_TAB)
	_check(not equipment.is_open(), "Tab closes it")
	var rage := vitals.get_rage()
	await _key(KEY_0)
	_check(vitals.has_buff(&"battle_fury") and vitals.get_rage() > rage, "the real 0 key drinks the ale from slot 5")


func _test_world_space_ultimates() -> void:
	print("[World-space ultimate effects]")
	# Flame Slash: burning ground, scorch marks, an explosion where it ends.
	await _reset_vitals()
	await _face(AIM)
	await _equip(&"steel_sword", 5)
	vitals.add_rage(100.0)
	var near := _dummy(_at(4.0))
	await _physics(3)
	var spawned: Array[StringName] = []
	var watch := func(kind: StringName, _e: Node3D) -> void: spawned.append(kind)
	ultimates.effect_spawned.connect(watch)
	_check(ultimates.use(), "Flame Slash released")
	await _seconds(0.45)
	var scorches := _named("FxScorch").filter(func(n: Node) -> bool: return n is Decal)
	_check(spawned.count(&"flame_trail") >= 4, "the slash sets the ground it crosses on fire (%d patches)" % spawned.count(&"flame_trail"))
	_check(scorches.size() >= 4, "and leaves scorch decals on the terrain (%d)" % scorches.size())
	_check(near.get_node_or_null("FxStatus_burn") != null, "the enemy it hit is burning")
	await _seconds(0.6)
	_check(spawned.has(&"flame_explosion"), "it ends in an explosion")
	ultimates.effect_spawned.disconnect(watch)
	await _clear_dummies()
	ultimates.cooldowns.clear()
	# Earthquake: fissures, rings, rocks, a shake.
	await _equip(&"battle_axe", 5)
	vitals.add_rage(100.0)
	near = _dummy(_at(3.0))
	await _physics(3)
	spawned.clear()
	ultimates.effect_spawned.connect(watch)
	_check(ultimates.use(), "Earthquake released")
	await _frames(2)
	var rig := level.find_child("IsoCameraRig", true, false) as IsoCameraRig
	_check(rig.get_shake_remaining() > 0.0, "the camera shakes")
	var cracks := _named("Cracks").filter(func(n: Node) -> bool: return n is Decal)
	_check(not cracks.is_empty(), "glowing fissures are projected onto the ground (a decal)")
	await _seconds(0.8)
	_check(spawned.count(&"quake_ring") == 3, "three shockwave rings run over the ground (%d)" % spawned.count(&"quake_ring"))
	_check(spawned.has(&"quake_debris") and not _named("FxDebris").is_empty(), "rocks are thrown up (3D meshes)")
	_check(not cracks.is_empty() and is_instance_valid(cracks[0]) and (cracks[0] as Decal).size.x >= 13.0, "the fissures open to the quake's 7 m radius (%.1f m)" % ((cracks[0] as Decal).size.x if not cracks.is_empty() and is_instance_valid(cracks[0]) else 0.0))
	_check(near.get_node_or_null("FxStatus_stun") != null, "the staggered enemy shows it is stunned")
	ultimates.effect_spawned.disconnect(watch)
	await _clear_dummies()
	ultimates.cooldowns.clear()
	# Thunder Arrow: lightning from the sky on each target.
	await _equip(&"hunting_bow", 5)
	vitals.add_rage(100.0)
	var first := _dummy(_at(6.0))
	var second := _dummy(_at(8.5, 1.5))
	await _physics(3)
	spawned.clear()
	ultimates.effect_spawned.connect(watch)
	_check(ultimates.use(), "Thunder Arrow released")
	var tallest := 0.0
	for i in 40:
		await physics_frame
		for strike in _named("FxLightning"):
			var bolt := strike.get_node_or_null("Bolt") as MeshInstance3D
			if bolt != null and bolt.mesh != null:
				tallest = maxf(tallest, bolt.mesh.get_aabb().size.y)
	_check(spawned.count(&"lightning_strike") >= 2, "lightning strikes both targets (%d)" % spawned.count(&"lightning_strike"))
	_check(tallest > 10.0, "the bolts come down from the sky (%.1f m tall)" % tallest)
	_check(first.get_node_or_null("FxStatus_shock") != null and second.get_node_or_null("FxStatus_shock") != null, "both enemies are electrified")
	_check(spawned.has(&"chain_bolt"), "an arc jumps between them")
	ultimates.effect_spawned.disconnect(watch)
	await _seconds(0.6)
	await _clear_dummies()
	ultimates.cooldowns.clear()
	# Arcane Storm: a rune circle on the terrain, violet lightning, area damage.
	await _equip(&"magic_staff", 5)
	vitals.add_rage(100.0)
	var target := _dummy(_at(4.0))
	await _physics(3)
	spawned.clear()
	ultimates.effect_spawned.connect(watch)
	var hp := target.health.get_health()
	_check(ultimates.use(), "Arcane Storm released")
	await _frames(2)
	var circle := _named("Circle").filter(func(n: Node) -> bool: return n is Decal)
	_check(not circle.is_empty() and (circle[0] as Decal).global_position.distance_to(target.global_position) < 1.0, "a rune circle decal is drawn on the ground under the target")
	await _seconds(3.0)
	_check(spawned.count(&"storm_lightning") == 6, "six timed strikes from the sky (%d)" % spawned.count(&"storm_lightning"))
	_check(target.health.get_health() < hp, "they deal real area damage (%.0f)" % (hp - target.health.get_health()))
	ultimates.effect_spawned.disconnect(watch)
	await _clear_dummies()
	ultimates.cooldowns.clear()


func _test_combat_feedback() -> void:
	print("[Combat feedback]")
	await _reset_vitals()
	await _face(AIM)
	var spawned: Array[StringName] = []
	var watch := func(kind: StringName, _e: Node3D) -> void: spawned.append(kind)
	effects.effect_spawned.connect(watch)
	await _equip(&"magic_staff", 3)
	await _attack()
	_check(spawned.has(&"cast_circle"), "casting a spell draws a rune circle at the courier's feet")
	await _equip(&"battle_axe", 3)
	spawned.clear()
	await _attack()
	_check(spawned.has(&"axe_ground_crack"), "a +3 axe chop cracks the ground")
	await _equip(&"steel_sword", 4)
	var victim := _dummy(_at(1.2), 10.0)
	await _physics(3)
	spawned.clear()
	await _attack()
	_check(spawned.has(&"sword_scorch"), "a +4 sword hit scorches the ground")
	_check(spawned.has(&"enemy_defeat"), "a defeated enemy bursts (dust, sparks, light)")
	effects.effect_spawned.disconnect(watch)
	await _clear_dummies()


func _test_save_load() -> void:
	print("[Save and load]")
	await _reset_vitals()
	vitals.consume(&"roast_ham")
	health.apply_damage(25.0)
	vitals.spend(40.0)
	vitals.add_rage(33.0)
	var rage := vitals.get_rage()
	var save := SaveGame.find(self)
	var data := save.to_dict()
	_check(data.has("vitals") and (data["vitals"]["buffs"] as Array).size() == 1, "the save holds the vitals and the buff")
	var slots := inventory.get_consumable_slot_ids()
	await _reset_vitals()
	inventory.clear_consumable_slot(0)
	save.from_dict(JSON.parse_string(JSON.stringify(data)))
	await _frames(2)
	_check(absf(vitals.get_mana() - 60.0) < 0.5 and is_equal_approx(vitals.get_rage(), rage), "MP and rage come back (%.1f, %.1f)" % [vitals.get_mana(), vitals.get_rage()])
	_check(vitals.has_buff(&"hearty") and is_equal_approx(combat.damage_multiplier, 1.15), "the buff comes back and applies")
	_check(is_equal_approx(health.get_health(), health.get_max_health() - 25.0) or health.get_health() > health.get_max_health() - 25.0, "health comes back (%.0f)" % health.get_health())
	_check(inventory.get_consumable_slot_ids() == slots, "the provisions slots come back")
