extends SceneTree
## Phase 8 milestone 1, controls, with real key events in the village:
## - Bindings: Space attack, Ctrl jump, Tab map, Q inventory, R package shield, T tool/weapon
##   switch, M free; no gameplay key is bound twice.
## - Tab opens and closes the map even while a button has keyboard focus (Tab is also the
##   GUI's focus-next key); Q opens and closes the inventory; Tab never opens the inventory.
## - T swaps the last weapon and the last tool: hand model, attack style, HUD mode line,
##   enhancement levels kept, remembered across save/load, refused in windows and dialogue.
## - Jump: from the ground only (no double jump), about 1.2 m high, keeps running speed,
##   lands, plays its poses, works with attacks and does not disturb the Shift dash.
##   godot --headless --path . --script res://tests/phase8_controls_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
## Open, flat ground in front of the Armory.
const ARENA := Vector3(5.6, 0, -11.0)

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var combat: CombatController
var character: KayKitCharacter
var equipment: EquipmentUI
var minimap: Node
var bar: QuickWeaponBar


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_controls_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	combat = CombatController.find_on(player)
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	equipment = level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	minimap = level.get_node("GameplayHUD/Minimap")
	bar = level.find_children("*", "QuickWeaponBar", true, false)[0] as QuickWeaponBar
	await _frames(20)
	player.teleport_to(ARENA)
	await _physics(10)

	_test_bindings()
	await _test_map_and_inventory_keys()
	await _test_quick_switch()
	await _test_jump()

	print("\n=== Phase 8 controls tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)


func _has_key(action: StringName, code: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false


func _held_path() -> String:
	var held := character.get_held_item_node()
	return held.scene_file_path if held != null else ""


# --- tests -------------------------------------------------------------------

func _test_bindings() -> void:
	print("[Bindings]")
	var expected := {
		&"combat_magic_bolt": KEY_SPACE, &"jump": KEY_CTRL, &"toggle_map": KEY_TAB,
		&"toggle_equipment": KEY_Q, &"package_shield": KEY_R, &"quick_switch_tool": KEY_T,
		&"combat_dash": KEY_SHIFT, &"interact": KEY_E, &"toggle_journal": KEY_J,
	}
	for action in expected:
		_check(_has_key(action, expected[action]), "%s is %s" % [action, OS.get_keycode_string(expected[action])])
	var bound_to_m: Array[StringName] = []
	var used := {}
	var clash: Array[String] = []
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			if key.physical_keycode == KEY_M:
				bound_to_m.append(action)
			# Shift is run and dash on purpose (hold to run, tap to dash).
			if used.has(key.physical_keycode) and key.physical_keycode != KEY_SHIFT:
				clash.append("%s/%s" % [used[key.physical_keycode], action])
			used[key.physical_keycode] = action
	_check(bound_to_m.is_empty(), "M is free (%s)" % [bound_to_m])
	_check(clash.is_empty(), "no key is bound to two gameplay actions (%s)" % [clash])


func _test_map_and_inventory_keys() -> void:
	print("[Tab map, Q inventory]")
	await _tap(KEY_TAB)
	_check(minimap.call(&"is_expanded") and not equipment.is_open(), "Tab opens the map, not the inventory")
	_check(not player.input_enabled, "the open map pauses the courier")
	await _tap(KEY_TAB)
	_check(not minimap.call(&"is_expanded"), "Tab closes the map")
	await _frames(2)
	_check(player.input_enabled, "closing the map returns control")
	# A focused button would take Tab for focus navigation; the map must still open.
	var focus := Button.new()
	focus.text = "focus probe"
	level.get_node("GameplayHUD").add_child(focus)
	focus.grab_focus()
	await _frames(1)
	await _tap(KEY_TAB)
	_check(minimap.call(&"is_expanded"), "Tab opens the map while a button has keyboard focus")
	await _tap(KEY_TAB)
	focus.queue_free()
	await _frames(2)
	await _tap(KEY_M)
	_check(not minimap.call(&"is_expanded") and not equipment.is_open(), "M opens nothing now")
	await _tap(KEY_Q)
	_check(equipment.is_open() and not minimap.call(&"is_expanded"), "Q opens the inventory")
	await _tap(KEY_TAB)
	_check(equipment.is_open() and not minimap.call(&"is_expanded"), "Tab does not open the map over the inventory")
	await _tap(KEY_Q)
	_check(not equipment.is_open(), "Q closes the inventory")
	await _frames(2)
	_check(player.input_enabled, "and returns control")


func _test_quick_switch() -> void:
	print("[T: tool / weapon quick switch]")
	for id in [&"iron_sword", &"battle_axe", &"miner_pickaxe", &"woodcutter_axe"]:
		inventory.add_item(inventory.get_definition(id))
	inventory.set_enhancement(&"iron_sword", 3)
	inventory.equip(&"iron_sword")
	await _frames(3)
	_check(bar.mode_label.text.begins_with("WEAPON MODE"), "the HUD shows weapon mode (%s)" % bar.mode_label.text)
	inventory.equip(&"miner_pickaxe")
	inventory.equip(&"iron_sword")
	await _frames(2)
	_check(bar.tooltip_text.contains("[T]") and bar.tooltip_text.contains("Miner's Pickaxe"), "the tooltip names the key and the tool T takes up (%s)" % bar.tooltip_text)
	_check(bar.get_global_rect().encloses(bar.mode_label.get_global_rect()), "the mode badge fits inside the bar")
	await _tap(KEY_T)
	var pickaxe := inventory.get_definition(&"miner_pickaxe")
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) == pickaxe, "T takes up the last tool (pickaxe)")
	_check(_held_path() == pickaxe.held_model.resource_path, "the pickaxe is in the courier's hand")
	_check(combat.get_attack_style() == CombatController.AttackStyle.TOOL, "Space now uses the tool")
	_check(bar.mode_label.text.begins_with("TOOL MODE") and bar.tooltip_text.contains("Iron Sword"), "the HUD shows tool mode; the tooltip names the sword to return to (%s)" % bar.tooltip_text)
	await _tap(KEY_T)
	var sword := inventory.get_definition(&"iron_sword")
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) == sword and _held_path() == sword.held_model.resource_path, "T returns to the sword")
	_check(combat.get_attack_style() == CombatController.AttackStyle.FAST_MELEE and inventory.get_enhancement(&"iron_sword") == 3, "fast melee again, still +3")
	_check(is_equal_approx(combat.melee_damage, sword.attack_damage * Enhancement.damage_multiplier(3)), "the +3 damage applies (%.0f)" % combat.melee_damage)
	# Weapon and tool are remembered independently.
	inventory.equip(&"battle_axe")
	inventory.equip(&"woodcutter_axe")
	await _tap(KEY_T)
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND).item_id == &"battle_axe", "the weapon remembered is the last one used (battle axe)")
	await _tap(KEY_T)
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND).item_id == &"woodcutter_axe", "the tool remembered is the last one used (woodcutter's axe)")
	var saved := inventory.to_dict()
	inventory.equip(&"iron_sword")
	inventory.from_dict(saved)
	await _frames(2)
	_check(inventory.last_weapon == &"battle_axe" and inventory.last_tool == &"woodcutter_axe", "both are saved and loaded")
	await _tap(KEY_T)
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND).item_id == &"battle_axe", "T after loading returns to the battle axe")
	# Refused while a window is open.
	equipment.open()
	await _frames(2)
	await _tap(KEY_T)
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND).item_id == &"battle_axe", "T does not swap while the inventory is open")
	equipment.close()
	await _frames(3)
	# Nothing to switch to.
	var data := inventory.to_dict()
	inventory.from_dict({"owned": ["iron_sword"], "equipped": {"MAIN_HAND": "iron_sword"}})
	await _frames(2)
	_check(bar.quick_switch() == null and inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND).item_id == &"iron_sword", "with no tool owned, T changes nothing")
	inventory.from_dict(data)
	await _frames(2)


func _test_jump() -> void:
	print("[Jump]")
	player.teleport_to(ARENA)
	await _physics(20)
	_check(player.is_on_floor(), "the courier stands on the ground")
	var ground := player.global_position.y
	var jumps := [0]
	var lands := [0]
	var on_jump := func() -> void: jumps[0] += 1
	var on_land := func(_air: float) -> void: lands[0] += 1
	player.jumped.connect(on_jump)
	player.landed.connect(on_land)
	_key(KEY_CTRL, true)
	await _physics(3)
	_key(KEY_CTRL, false)
	_check(jumps[0] == 1 and player.is_jumping(), "Ctrl jumps")
	_check(character.one_shot_action == &"jump_start" or character.current_loop == &"airborne", "the take-off pose plays")
	var peak := ground
	var second_pressed := false
	for i in 120:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		if not second_pressed and player.velocity.y < 1.0 and not player.is_on_floor():
			second_pressed = true
			await _tap(KEY_CTRL)
		if player.is_on_floor() and i > 10:
			break
	_check(absf(peak - ground - 1.18) < 0.2, "it rises about 1.2 m (%.2f m)" % (peak - ground))
	_check(jumps[0] == 1, "a mid-air press does not jump again")
	await _physics(4)
	_check(lands[0] >= 1 and player.is_on_floor() and absf(player.global_position.y - ground) < 0.05, "it lands back on the ground")
	# A jump while running keeps the running speed.
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _physics(40)
	var speed := player.get_horizontal_speed()
	_key(KEY_CTRL, true)
	await _physics(10)
	_key(KEY_CTRL, false)
	var air_speed := player.get_horizontal_speed()
	_check(not player.is_on_floor() and air_speed > speed * 0.9, "a running jump keeps its speed (%.1f -> %.1f m/s)" % [speed, air_speed])
	for i in 90:
		await physics_frame
		if player.is_on_floor():
			break
	Input.action_release(&"move_right")
	Input.action_release(&"run")
	await _physics(30)
	# Attacks still work in the air; Shift still dashes on the ground.
	inventory.equip(&"iron_sword")
	await _physics(30)
	_key(KEY_CTRL, true)
	await _physics(6)
	_key(KEY_CTRL, false)
	_check(combat.try_attack(Vector3.FORWARD), "the courier can swing mid-jump")
	for i in 90:
		await physics_frame
		if player.is_on_floor():
			break
	await _physics(60)
	var dashes := [0]
	combat.dash_started.connect(func() -> void: dashes[0] += 1)
	var jumps_before: int = jumps[0]
	Input.action_press(&"move_right")
	await _physics(4)
	await _tap(KEY_SHIFT)
	await _physics(4)
	Input.action_release(&"move_right")
	_check(dashes[0] == 1 and jumps[0] == jumps_before, "Shift dashes and does not jump")
	# No jump while the courier's input is off (a window is open).
	await _physics(40)
	equipment.open()
	await _frames(2)
	await _tap(KEY_CTRL)
	await _physics(4)
	_check(jumps[0] == jumps_before and player.is_on_floor(), "no jump while the inventory is open")
	equipment.close()
	await _frames(3)
