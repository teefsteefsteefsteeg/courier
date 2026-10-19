extends SceneTree
## Renders Phase 8 milestone 1 (controls) in the real village with real key events (GPU
## window, NOT --headless), revised layout: M map, Tab inventory, Q tool/weapon switch with
## the HUD mode line (and the inventory view while open), the bow's enhancement effects from
## the gameplay camera, a Ctrl jump in mid-air, and the key guide. SaveGame is removed and UISettings does
## not persist, so the player's real save and settings are never touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_controls.gd -- <output_dir>

const ARENA := Vector3(5.6, 0, -11.0)

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var out_dir: String
var problems: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase8")
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
	await _wait(40)
	var inventory := CourierInventory.find(self)
	for id in [&"iron_sword", &"miner_pickaxe"]:
		inventory.add_item(inventory.get_definition(id))
	inventory.equip(&"miner_pickaxe")
	inventory.equip(&"iron_sword")
	player.teleport_to(ARENA)
	rig.set_zoom(10.0)
	rig.snap_to_target()
	await _wait(40)
	var hud := level.get_node("GameplayHUD")
	var minimap := hud.get_node("Minimap")
	var equipment := hud.get_node("EquipmentUI") as EquipmentUI

	# Phase 8 controls revision: M map, Tab inventory, Q tool/weapon switch (and the
	# inventory's view while it is open). Shots 01..06 showed the first layout.
	await _shot("59_revised_key_guide_weapon_mode")
	await _key(KEY_M)
	_expect(minimap.call(&"is_expanded") and not equipment.is_open(), "M opened the map")
	await _wait(10)
	await _shot("60_m_opens_map")
	await _key(KEY_M)
	_expect(not minimap.call(&"is_expanded"), "M closed the map")
	await _key(KEY_TAB)
	_expect(equipment.is_open() and not minimap.call(&"is_expanded"), "Tab opened the inventory")
	await _wait(10)
	await _shot("61_tab_opens_inventory")
	await _key(KEY_Q)
	_expect(equipment.view == EquipmentUI.View.TOOLS, "Q switched the inventory view")
	await _wait(6)
	await _shot("62_q_switches_inventory_view")
	await _key(KEY_TAB)
	_expect(not equipment.is_open(), "Tab closed the inventory")
	await _wait(6)
	await _key(KEY_Q)
	var main := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND)
	_expect(main != null and main.item_id == &"miner_pickaxe", "Q took up the pickaxe")
	await _wait(20)
	await _shot("63_q_tool_mode_pickaxe_in_hand")
	await _key(KEY_Q)
	main = inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND)
	_expect(main != null and main.item_id == &"iron_sword", "Q returned to the sword")
	await _wait(20)
	# The bow's enhancement effects from the gameplay camera (default zoom), idle and running.
	inventory.add_item(inventory.get_definition(&"hunting_bow"))
	inventory.equip(&"hunting_bow")
	rig.set_zoom(14.0)
	rig.snap_to_target()
	for level_index in [4, 5]:
		inventory.set_enhancement(&"hunting_bow", level_index)
		await _wait(30)
		var glow := EnhancementVisuals.find(self).weapon_glow
		_expect(glow != null and glow.shows_over_body, "bow +%d effects draw over the body" % level_index)
		await _shot("%d_bow_plus%d_gameplay_camera" % [62 + level_index, level_index])
	Input.action_press(&"move_back")
	await _wait(30)
	await _shot("68_bow_plus5_running_towards_camera")
	Input.action_release(&"move_back")
	inventory.equip(&"iron_sword")
	rig.set_zoom(10.0)
	player.teleport_to(ARENA)
	rig.snap_to_target()
	await _wait(30)
	var ground := player.global_position.y
	var peak := ground
	await _key_down(KEY_CTRL)
	for i in 30:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		if player.velocity.y <= 0.3:
			break
	await _shot("69_ctrl_jump_mid_air")
	await _key_up(KEY_CTRL)
	_expect(peak - ground > 0.8, "the jump rose %.2f m" % (peak - ground))
	for i in 90:
		await physics_frame
		if player.is_on_floor():
			break
	_expect(player.is_on_floor(), "landed")
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _key(code: Key) -> void:
	await _key_down(code)
	await _key_up(code)


func _key_down(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(2)


func _key_up(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait(2)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
