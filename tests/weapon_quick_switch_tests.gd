extends SceneTree
## Weapon inventory and quick switching: item weapon types, quick-slot rules on the real
## CourierInventory (owned weapons only, no duplicates, shields refused, two-handed bows),
## buying two weapons and putting them on slots 1 and 2, switching with keys 1-5 and
## clicks while standing and while walking, the held mesh and the attack style changing
## (sword fast melee, axe heavy melee, staff and bare hands bolts, bow arrows) with real
## hits on a target, safe switching during a swing, a dash and a cooldown, switching and
## the Equipment window blocked by dialogue and modal windows, the HUD bar layout, and
## save/load plus a scene reload restoring the same state.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/weapon_quick_switch_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const CATALOG := "res://data/shops/armory.tres"
const SAVE_PATH := "user://weapon_quick_switch_test_save.json"
const ARMORY_SPOT := Vector3(5.6, 0, -11.0)
const BOLT_SCENE := "res://scenes/gameplay/combat/magic_bolt.tscn"
const ARROW_SCENE := "res://scenes/gameplay/combat/arrow.tscn"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var wallet: CourierWallet
var combat: CombatController
var character: KayKitCharacter
var hud: GameplayHUD
var bar: QuickWeaponBar
var equipment_ui: EquipmentUI
var shop: ShopUI
var catalog: ShopCatalog
var bow: ItemDefinition
var target: StaticBody3D
var target_health: CombatHealth


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	catalog = load(CATALOG) as ShopCatalog
	bow = catalog.get_item(&"hunting_bow")
	_test_item_types()
	_test_inventory_rules()
	await _load_level()
	await _test_buy_and_assign()
	await _test_switch_keys_and_clicks()
	await _test_attack_behaviour()
	await _test_safe_switching()
	await _test_blocked_switching()
	await _test_hud()
	_test_bindings()
	await _test_save_and_reload()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("\n=== Weapon quick switch tests: %d passed, %d failed ===" % [_passes, _failures])
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
	await process_frame


# --- data and rules (no level) -------------------------------------------------------

func _test_item_types() -> void:
	print("[Weapon types]")
	var expected := {&"wooden_sword": ItemDefinition.WeaponType.SWORD, &"iron_sword": ItemDefinition.WeaponType.SWORD,
			&"steel_sword": ItemDefinition.WeaponType.SWORD, &"battle_axe": ItemDefinition.WeaponType.AXE,
			&"magic_staff": ItemDefinition.WeaponType.STAFF, &"wooden_shield": ItemDefinition.WeaponType.NONE}
	for item_id: StringName in expected:
		var item := catalog.get_item(item_id)
		_check(item != null and item.weapon_type == expected[item_id], "%s is a %s" % [item_id, ItemDefinition.WeaponType.keys()[expected[item_id]]])
	var axe := catalog.get_item(&"battle_axe")
	var sword := catalog.get_item(&"iron_sword")
	_check(axe.attack_damage > sword.attack_damage and axe.attack_cooldown > sword.attack_cooldown and axe.attack_windup > sword.attack_windup,
			"the axe hits harder and slower than the sword")
	_check(not catalog.get_item(&"wooden_shield").is_weapon(), "the shield is not a quick-slot weapon")
	_check(bow != null and bow.weapon_type == ItemDefinition.WeaponType.BOW and bow.two_handed and bow.price == 250 and bow.icon != null 			and bow.held_model != null and bow.held_model.resource_path.ends_with("bow_A_withString.gltf"), "the Armory sells a two-handed Hunting Bow (250 g) with icon and model")


func _test_inventory_rules() -> void:
	print("[Quick-slot rules]")
	var inv := CourierInventory.new()
	for item in catalog.items:
		inv.register_item(item)
	inv.register_item(bow)
	root.add_child(inv)
	_check(not inv.assign_quick_slot(0, &"iron_sword") and inv.get_quick_slot(0) == null, "an unowned weapon cannot be assigned")
	_check(not inv.select_quick_slot(0) and not inv.equip(&"iron_sword"), "an unowned weapon cannot be selected or equipped")
	inv.add_item(catalog.get_item(&"iron_sword"))
	inv.add_item(catalog.get_item(&"wooden_shield"))
	inv.add_item(catalog.get_item(&"battle_axe"))
	_check(inv.get_quick_slot_ids() == [&"iron_sword", &"battle_axe", &"", &"", &""], "bought weapons fill the first empty slots; the shield does not (%s)" % [inv.get_quick_slot_ids()])
	_check(not inv.assign_quick_slot(2, &"wooden_shield"), "a shield cannot go on a quick slot")
	_check(not inv.assign_quick_slot(5, &"iron_sword") and not inv.assign_quick_slot(-1, &"iron_sword"), "slot index outside 1-5 is refused")
	_check(inv.assign_quick_slot(4, &"iron_sword") and inv.get_quick_slot_ids() == [&"", &"battle_axe", &"", &"", &"iron_sword"],
			"re-assigning moves the weapon, never duplicating it")
	_check(inv.assign_quick_slot(1, &"iron_sword") and inv.get_quick_slot_ids() == [&"", &"iron_sword", &"", &"", &""], "replacing a slot drops its old weapon")
	inv.clear_quick_slot(1)
	_check(inv.get_quick_slot(1) == null and inv.has_item(&"iron_sword"), "clearing a slot keeps the weapon owned")
	_check(inv.get_owned_ids().count(&"iron_sword") == 1, "ownership is recorded once")
	inv.add_item(bow)
	inv.equip(&"wooden_shield")
	_check(inv.equip(&"hunting_bow") and inv.get_equipped(ItemDefinition.Slot.OFF_HAND) == null, "a two-handed bow takes the shield off")
	_check(not inv.equip(&"wooden_shield"), "the shield cannot be equipped beside a two-handed bow")
	var data := {"owned": ["iron_sword", "battle_axe"], "equipped": {"MAIN_HAND": "battle_axe"}}
	inv.from_dict(data)
	_check(inv.get_quick_slot_ids() == [&"iron_sword", &"battle_axe", &"", &"", &""] and inv.is_equipped(&"battle_axe"),
			"a save from before quick slots fills them with the owned weapons")
	# Freed now, not queued: the level's services look the inventory up by group.
	root.remove_child(inv)
	inv.free()


# --- in the village ------------------------------------------------------------------

func _load_level(save_path := "") -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	if not save_path.is_empty():
		var save := level.find_children("*", "SaveGame", true, false)[0] as SaveGame
		save.path = save_path
		save.force_enabled_headless = true
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	await _frames(10)
	inventory = CourierInventory.find(self)
	wallet = CourierWallet.find(self)
	combat = CombatController.find_on(player)
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	hud = level.get_node("GameplayHUD") as GameplayHUD
	bar = hud.quick_weapon_bar
	equipment_ui = hud.equipment_ui
	shop = hud.get_node("ShopUI") as ShopUI
	combat.simulate = true


func _test_buy_and_assign() -> void:
	print("[Buy two weapons, slots 1 and 2]")
	_check(bar != null and equipment_ui != null, "HUD has the quick bar and the Equipment window")
	_check(inventory.get_owned_ids().is_empty() and bar.info_label.text == "Bare hands", "a new game starts bare-handed (%s, '%s')" % [inventory.get_owned_ids(), bar.info_label.text])
	wallet.add_gold(450)
	var merchant := level.get_node("Armory").get(&"merchant").get_node("ShopMerchant") as Merchant
	shop.open(merchant, player)
	await _frames(1)
	shop.activate(&"wooden_sword")
	shop.activate(&"battle_axe")
	shop.close()
	await _frames(2)
	_check(inventory.has_item(&"wooden_sword") and inventory.has_item(&"battle_axe") and wallet.gold == 0, "bought the wooden sword and the battle axe")
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) == null, "buying does not equip")
	inventory.clear_quick_slot(0)
	inventory.clear_quick_slot(1)
	equipment_ui.open()
	await _frames(1)
	_check(equipment_ui.is_open() and player.input_enabled == false, "Tab window opens and pauses the courier")
	equipment_ui.activate_slot(&"wooden_sword", 0)
	equipment_ui.activate_slot(&"battle_axe", 1)
	_check(inventory.get_quick_slot_ids() == [&"wooden_sword", &"battle_axe", &"", &"", &""], "assigned the sword to slot 1 and the axe to slot 2 in the Equipment window")
	var unowned: Dictionary = equipment_ui.rows[&"steel_sword"]
	_check((unowned["status"] as Label).text.begins_with("Not owned") and (unowned["equip"] as Button).disabled \
			and (unowned["slots"] as Array).all(func(b: Button) -> bool: return b.disabled), "unowned items are marked and cannot be equipped or slotted")
	_check((equipment_ui.rows[&"wooden_sword"]["status"] as Label).text.begins_with("Owned"), "owned items are marked Owned")
	equipment_ui.activate_slot(&"steel_sword", 2)
	_check(inventory.get_quick_slot(2) == null, "pressing an unowned item's slot does nothing")
	equipment_ui.close()
	await _frames(2)
	_check(not equipment_ui.is_open() and player.input_enabled, "closing the window returns control")


func _test_switch_keys_and_clicks() -> void:
	print("[Switching with keys and clicks]")
	player.teleport_to(ARMORY_SPOT)
	await _frames(2)
	await _press_key(KEY_1)
	_check(_holding(&"wooden_sword") and combat.get_attack_style() == CombatController.AttackStyle.FAST_MELEE, "key 1 (standing): wooden sword in hand, fast melee")
	_check(bar.slot_buttons[0].get_meta(&"equipped") and not bar.slot_buttons[1].get_meta(&"equipped"), "slot 1 is highlighted")
	_check(bar.info_label.text == "Wooden Sword" and bar.stats_label.text.contains("fast melee"), "bar names the sword and its stats (%s)" % bar.stats_label.text)
	# Walking: hold forward, press 2 mid-stride.
	var start := player.global_position
	Input.action_press(&"move_back")
	await _frames(15)
	await _press_key(KEY_2)
	await _frames(15)
	Input.action_release(&"move_back")
	_check(_holding(&"battle_axe") and combat.get_attack_style() == CombatController.AttackStyle.HEAVY_MELEE, "key 2 while walking: axe in hand, heavy melee")
	_check(player.global_position.distance_to(start) > 1.0, "the courier kept walking through the switch (%.1f m)" % player.global_position.distance_to(start))
	await _press_key(KEY_3)
	_check(_holding(&"battle_axe"), "an empty slot (3) changes nothing")
	_check(bar.slot_buttons[2].disabled and bar.slot_buttons[2].text == "-", "empty slots are dim and disabled")
	bar.slot_buttons[0].pressed.emit()
	await _frames(2)
	_check(_holding(&"wooden_sword"), "clicking slot 1 switches back to the sword")


func _test_attack_behaviour() -> void:
	print("[Attack behaviour follows the weapon]")
	player.teleport_to(ARMORY_SPOT)
	await _frames(3)
	_spawn_target(Vector3(0, 0, 1.2))
	var forward := Vector3(0, 0, 1)
	# Wooden sword: fast melee.
	inventory.equip(&"wooden_sword")
	await _wait_ready()
	var hp := target_health.get_health()
	_check(combat.try_attack(forward), "sword swing starts")
	_check(character.one_shot_action == &"melee_fast", "sword plays the fast swing animation")
	await _seconds(0.25)
	var sword := catalog.get_item(&"wooden_sword")
	_check(is_equal_approx(hp - target_health.get_health(), sword.attack_damage), "sword hit for %.0f (%.0f)" % [sword.attack_damage, hp - target_health.get_health()])
	_check(is_equal_approx(combat.melee_cooldown, sword.attack_cooldown) and is_equal_approx(combat.melee_range, sword.attack_range), "sword sets the attack speed and reach")
	# Battle axe: heavy melee.
	inventory.equip(&"battle_axe")
	await _wait_ready()
	hp = target_health.get_health()
	_check(combat.try_attack(forward), "axe swing starts")
	_check(character.one_shot_action == &"melee_heavy", "axe plays the heavy chop animation")
	await _seconds(0.15)
	_check(is_equal_approx(target_health.get_health(), hp), "the axe hit has not landed during its wind-up")
	await _seconds(0.35)
	var axe := catalog.get_item(&"battle_axe")
	_check(is_equal_approx(hp - target_health.get_health(), axe.attack_damage), "axe hit for %.0f (%.0f)" % [axe.attack_damage, hp - target_health.get_health()])
	_check(combat.get_magic_bolt_cooldown_remaining() > 0.4, "the axe's cooldown is long (%.2f s left)" % combat.get_magic_bolt_cooldown_remaining())
	var combat_hud := level.find_child("CombatHUD", true, false)
	_check(combat_hud != null and not bool(combat_hud.call(&"is_bolt_ready")) and is_equal_approx(float(combat_hud.get(&"bolt_total")), axe.attack_cooldown),
			"the combat HUD counts down the axe's real cooldown")
	# Out of reach / behind: no hit.
	await _wait_ready()
	hp = target_health.get_health()
	combat.try_attack(-forward)
	await _seconds(0.5)
	_check(is_equal_approx(target_health.get_health(), hp), "a swing away from the target misses")
	# Staff: Magic Bolt projectile.
	inventory.add_item(catalog.get_item(&"magic_staff"))
	inventory.equip(&"magic_staff")
	await _wait_ready()
	var bolts := _projectiles(BOLT_SCENE)
	_check(combat.try_attack(forward) and _projectiles(BOLT_SCENE) > bolts and character.one_shot_action == &"attack", "the staff casts a magic bolt")
	# Bow: arrow projectile with the arrow model.
	inventory.add_item(bow)
	inventory.equip(&"hunting_bow")
	await _wait_ready()
	_check(combat.get_attack_style() == CombatController.AttackStyle.ARROW and is_equal_approx(combat.arrow_damage, bow.attack_damage), "a bow switches to arrows with its damage")
	var arrows := _projectiles(ARROW_SCENE)
	_check(combat.try_attack(forward) and _projectiles(ARROW_SCENE) > arrows and character.one_shot_action == &"shoot", "the bow fires an arrow")
	# Bare hands: bolt again.
	inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	await _wait_ready()
	_check(combat.get_attack_style() == CombatController.AttackStyle.MAGIC_BOLT, "bare hands cast the magic bolt")
	await _frames(30)


func _test_safe_switching() -> void:
	print("[Switching mid-swing, mid-dash and on cooldown]")
	var forward := Vector3(0, 0, 1)
	target_health.reset()
	inventory.equip(&"battle_axe")
	await _wait_ready()
	var cancelled := [false]
	combat.melee_cancelled.connect(func() -> void: cancelled[0] = true, CONNECT_ONE_SHOT)
	var hp := target_health.get_health()
	combat.try_attack(forward)
	await _seconds(0.1)
	await _press_key(KEY_1)
	await _seconds(0.5)
	_check(cancelled[0] and is_equal_approx(target_health.get_health(), hp), "switching during the axe wind-up cancels the swing: no hit")
	_check(_holding(&"wooden_sword"), "the switch still went through")
	# On cooldown: the switch never shortens it.
	await _wait_ready()
	combat.try_attack(forward)
	await _frames(1)
	var left := combat.get_magic_bolt_cooldown_remaining()
	await _press_key(KEY_2)
	_check(combat.get_magic_bolt_cooldown_remaining() >= minf(left, combat.switch_delay) - 0.05, "switching during a cooldown never skips it")
	await _wait_ready()
	await _press_key(KEY_1)
	_check(combat.is_magic_bolt_ready(), "with no cooldown running, a switched-in weapon can attack at once")
	combat.switch_delay = 0.25
	await _press_key(KEY_2)
	_check(not combat.is_magic_bolt_ready() and combat.get_magic_bolt_cooldown_remaining() > 0.1, "an optional switch_delay makes the next attack wait")
	combat.switch_delay = 0.0
	await _press_key(KEY_1)
	# Mid-dash.
	await _wait_ready()
	_check(combat.try_dash(Vector3.RIGHT), "dash starts")
	await _press_key(KEY_2)
	_check(_holding(&"battle_axe"), "switching mid-dash works")
	await _seconds(0.4)
	_check(not combat.is_dashing() and character.one_shot_action != &"dash", "the dash finished normally")


func _test_blocked_switching() -> void:
	print("[Blocked during dialogue and windows]")
	inventory.equip(&"wooden_sword")
	await _frames(2)
	var dialogue := level.get_node("DialogueBox") as DialogueBox
	dialogue.show_line("Villager", "A long line so the box stays open for the test.")
	await _frames(2)
	await _press_key(KEY_2)
	_check(dialogue.is_open() and _holding(&"wooden_sword"), "keys 1-5 do nothing while a dialogue line is open")
	equipment_ui.open()
	_check(not equipment_ui.is_open(), "the Equipment window does not open over dialogue")
	bar.slot_buttons[1].pressed.emit()
	await _frames(1)
	_check(_holding(&"wooden_sword"), "clicking a slot does nothing during dialogue")
	dialogue.close()
	await _frames(2)
	var merchant := level.get_node("Armory").get(&"merchant").get_node("ShopMerchant") as Merchant
	shop.open(merchant, player)
	await _frames(1)
	await _press_key(KEY_2)
	_check(shop.is_open() and _holding(&"wooden_sword"), "keys 1-5 do nothing while the shop is open")
	shop.close()
	await _frames(2)
	equipment_ui.open()
	await _frames(1)
	await _press_key(KEY_2)
	_check(_holding(&"wooden_sword"), "keys 1-5 do nothing while the Equipment window is open")
	await _press_key(KEY_TAB)
	_check(not equipment_ui.is_open(), "Tab closes the Equipment window")
	await _frames(2)
	var journal := level.get_node("QuestJournal") as QuestJournal
	journal.open()
	await _frames(1)
	await _press_key(KEY_2)
	_check(_holding(&"wooden_sword"), "keys 1-5 do nothing while the journal is open")
	journal.close()
	await _frames(2)
	await _press_key(KEY_2)
	_check(_holding(&"battle_axe"), "switching works again once everything is closed")


func _test_hud() -> void:
	print("[HUD bar]")
	for index in CourierInventory.QUICK_SLOT_COUNT:
		var key_icon := bar.slot_buttons[index].get_node(^"Key") as TextureRect
		_check(key_icon.texture != null, "slot %d shows its key cap" % (index + 1))
	_check(bar.slot_buttons[0].icon == catalog.get_item(&"wooden_sword").icon and bar.slot_buttons[1].icon == catalog.get_item(&"battle_axe").icon, "slots show the weapons' icons")
	var combat_hud := level.find_child("CombatHUD", true, false)
	var minimap := hud.get_node("Minimap")
	var journal := level.get_node("QuestJournal") as QuestJournal
	for resolution in [Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 720)]:
		root.size = resolution
		root.content_scale_size = resolution
		await _frames(3)
		var view := Rect2(Vector2.ZERO, Vector2(resolution))
		var rect := bar.get_global_rect()
		var others: Array[Control] = [hud.quest_tracker, hud.wallet_display, minimap.compact, journal.hint_label, hud.movement_guide]
		if combat_hud != null and combat_hud.get("panel") is Control:
			others.append(combat_hud.get("panel"))
		var clear := true
		for other in others:
			if other.is_visible_in_tree() and rect.intersects(other.get_global_rect()):
				clear = false
				printerr("    overlaps ", other.name)
		_check(view.encloses(rect) and clear, "quick bar fits and overlaps nothing at %s" % resolution)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	await _frames(2)


func _test_bindings() -> void:
	print("[Input bindings]")
	var used := {}
	var clash: Array[String] = []
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			var code := key.physical_keycode
			if used.has(code) and (String(action).begins_with("quick_slot") or String(used[code]).begins_with("quick_slot") or action == &"toggle_equipment" or used[code] == &"toggle_equipment"):
				clash.append("%s/%s" % [used[code], action])
			used[code] = action
	_check(clash.is_empty(), "keys 1-5 and Tab (inventory) clash with no other action (%s)" % [clash])
	for index in CourierInventory.QUICK_SLOT_COUNT:
		_check(InputHints.key_for(StringName("quick_slot_%d" % (index + 1))) == str(index + 1), "quick_slot_%d is key %d" % [index + 1, index + 1])
	_check(InputHints.key_for(&"toggle_equipment") == "Tab", "Equipment is on Tab")
	_check(InputHints.key_for(&"toggle_map") == "M" and InputHints.key_for(&"quick_switch_tool") == "Q" and InputHints.key_for(&"package_shield") == "R" and InputHints.key_for(&"jump") == "Ctrl", "Phase 8 keys: M map, Q tool/weapon, R shield, Ctrl jump")


func _test_save_and_reload() -> void:
	print("[Save, load and scene reload]")
	inventory.assign_quick_slot(4, &"magic_staff")
	inventory.equip(&"battle_axe")
	var save := level.find_children("*", "SaveGame", true, false)[0] as SaveGame
	save.path = SAVE_PATH
	save.enabled = true
	_check(save.save_game(), "game saved")
	var saved_slots := inventory.get_quick_slot_ids()
	var saved_owned := inventory.get_owned_ids()
	inventory.from_dict({})
	await _frames(2)
	_check(inventory.get_owned_ids().is_empty() and not _holding(&"battle_axe"), "inventory emptied before loading")
	_check(save.load_game(), "save loaded")
	await _frames(2)
	_check(inventory.get_owned_ids() == saved_owned and inventory.get_quick_slot_ids() == saved_slots, "owned weapons and quick slots restored (%s)" % [inventory.get_quick_slot_ids()])
	_check(_holding(&"battle_axe") and combat.get_attack_style() == CombatController.AttackStyle.HEAVY_MELEE, "the equipped axe is back in hand with its heavy attack")
	# Reload the whole scene from the save file: nothing is reset.
	save.enabled = false
	level.queue_free()
	await _frames(3)
	await _load_level(SAVE_PATH)
	await _frames(5)
	_check(inventory.get_owned_ids() == saved_owned and inventory.get_quick_slot_ids() == saved_slots, "a reloaded scene keeps the purchased weapons and slots")
	_check(_holding(&"battle_axe") and bar.info_label.text == "Battle Axe" and bar.slot_buttons[1].get_meta(&"equipped"), "and shows the equipped axe in hand and on the bar")
	await _press_key(KEY_5)
	_check(_holding(&"magic_staff"), "slot 5 (staff) works after the reload")


# --- helpers -----------------------------------------------------------------------

func _press_key(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await _frames(1)
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await _frames(1)


func _holding(item_id: StringName) -> bool:
	var item := inventory.get_definition(item_id)
	var held := character.get_held_item_node()
	return item != null and inventory.is_equipped(item_id) and held != null and held.scene_file_path == item.held_model.resource_path


func _spawn_target(offset: Vector3) -> void:
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
	await _frames(2)


## Live projectiles instanced from scene_path.
func _projectiles(scene_path: String) -> int:
	return level.find_children("*", "CombatProjectile", true, false).filter(func(p: Node) -> bool:
		return p.scene_file_path == scene_path and not (p as CombatProjectile).is_finished()).size()


func _wait_ready() -> void:
	for i in 240:
		if combat.is_magic_bolt_ready() and not combat.is_melee_pending():
			break
		await physics_frame
	await _frames(1)


## Waits duration seconds of physics time (combat advances by the physics delta).
func _seconds(duration: float) -> void:
	for i in ceili(duration * Engine.physics_ticks_per_second):
		await physics_frame
