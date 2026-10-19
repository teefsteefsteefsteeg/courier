extends SceneTree
## Phase 5H rendered walkthrough in the real village (GPU window, NOT --headless): the
## Armory entrance, the respaced village, the Toolwright's shop, then every tool used with
## real key presses (quick slot keys, E, Space): fishing from the bank (cast, bite, hook),
## chopping a marked tree, mining an ore rock, digging clay, repairing the pond jetty, and
## fishing from the repaired jetty; the Equipment window with tools and materials; and a save
## and reload. Prints an "H5" line per step (what happened), so the run doubles as the
## gameplay validation. Uses its own save file; a windowed debug run is development mode
## (500 gold to buy the tools).
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase5h_screenshots.gd -- <output_dir>

const SAVE_PATH := "user://capture_phase5h_save.json"

var out_dir: String
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var user: ToolUser
var inventory: CourierInventory
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5h")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_delete_save()
	await _load_level()
	await _armory_and_village()
	await _shop()
	await _fishing_bank()
	await _woodcutting()
	await _mining_and_digging()
	await _repair_and_jetty()
	await _equipment()
	await _save_and_reload()
	_delete_save()
	print("H5 done, %d problems" % failures)
	quit(failures)


func _load_level() -> void:
	if level != null:
		root.remove_child(level)
		level.free()
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	var save := level.get_node("GameplayServices/SaveGame") as SaveGame
	save.path = SAVE_PATH
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	rig.max_zoom_size = 40.0
	user = ToolUser.find_on(player)
	user.rng.seed = 5
	inventory = CourierInventory.find(self)
	await _wait(60)


# --- Tasks 1-3 --------------------------------------------------------------------------

func _armory_and_village() -> void:
	var armory := level.get_node("Armory") as Armory
	var front := armory.get_shop_front().global_position
	player.teleport_to(front + Vector3(0.4, 0, 4.0))
	rig.set_zoom(12.0)
	rig.snap_to_target()
	await _wait(20)
	var detector := player.interaction
	var reached := await _walk_until(front, func() -> bool: return detector.focused == armory.merchant.interactable, 400)
	await _wait(30)
	_report(reached, "walked up to Brenna's counter from the road; prompt '%s'" % (level.get_node("InteractionPrompt") as InteractionPrompt).label.text)
	await _shot("01_armory_entrance")
	player.teleport_to(Vector3(-1.5, 0, -14.6))
	rig.set_zoom(27.0)
	rig.snap_to_target()
	await _wait(60)
	await _shot("02_village_north_spacing")
	player.teleport_to(Vector3(-4.0, 0, 7.5))
	rig.set_zoom(30.0)
	rig.snap_to_target()
	await _wait(60)
	await _shot("03_village_south_spacing")


# --- Toolwright ------------------------------------------------------------------------

func _shop() -> void:
	var stall := level.get_node("ToolSites/ToolStall") as ToolStall
	player.teleport_to(stall.get_shop_front().global_position + Vector3(0.6, 0, -2.5))
	rig.set_zoom(11.0)
	rig.snap_to_target()
	await _wait(20)
	var detector := player.interaction
	var reached := await _walk_until(stall.get_shop_front().global_position, func() -> bool: return detector.focused == stall.merchant.interactable, 400)
	await _wait(30)
	_report(reached, "walked up to Toolwright Hobb; prompt '%s'" % (level.get_node("InteractionPrompt") as InteractionPrompt).label.text)
	await _shot("04_toolwright_stall")
	await _key(KEY_E)
	await _wait(10)
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	_report(shop.is_open() and shop.title_label.text == "Toolwright Hobb", "Hobb's shop opened (%s), gold %d" % [shop.title_label.text, CourierWallet.find(self).gold])
	for id in [&"fishing_rod", &"woodcutter_axe", &"miner_pickaxe", &"garden_shovel", &"carpenter_hammer", &"mason_trowel"]:
		shop.activate(id)
	await _wait(10)
	_report(inventory.has_item(&"fishing_rod") and inventory.has_item(&"mason_trowel"), "bought six tools, gold left %d; quick slots %s" % [CourierWallet.find(self).gold, inventory.get_quick_slot_ids()])
	await _shot("05_toolwright_shop")
	shop.close()
	await _wait(10)


# --- fishing from the bank -------------------------------------------------------------

func _fishing_bank() -> void:
	# The rod went to quick slot 1 (bought first).
	await _key(KEY_1)
	var held := _held_name()
	_report(inventory.get_equipped_tool() != null and inventory.get_equipped_tool().item_id == &"fishing_rod", "key 1 equips the Fishing Rod (held model %s)" % held)
	# Dry land first: the cast is refused.
	player.teleport_to(Vector3(-24.0, 0, -12.0))
	await _wait(10)
	await _key(KEY_SPACE)
	_report(not user.is_busy(), "Space on dry land does not cast (%s)" % _last_toast())
	# West bank, facing the water.
	var pond := level.find_children("*", "Pond", true, false)[0] as Pond
	var centre := pond.global_position
	player.teleport_to(centre + Vector3(-5.6, 0, 0.6))
	_face(centre)
	rig.set_zoom(11.0)
	rig.snap_to_target()
	user.bite_wait_min = 2.5
	user.bite_wait_max = 2.5
	await _wait(20)
	await _key(KEY_SPACE)
	_report(user.state == ToolUser.State.FISHING, "Space with the rod at the bank casts the line")
	await _until(func() -> bool: return not (user.fish_state != ToolUser.FishState.WAITING))
	await _wait(30)
	await _shot("06_fishing_waiting")
	await _until(func() -> bool: return not (user.fish_state != ToolUser.FishState.BITE))
	await _wait(12)
	await _shot("07_fishing_bite")
	await _key(KEY_E)
	var reeling := user.fish_state == ToolUser.FishState.REELING
	await _until(func() -> bool: return not (user.is_busy()))
	var fish := inventory.get_material_count(&"pond_perch") + inventory.get_material_count(&"silver_trout") + inventory.get_material_count(&"golden_carp")
	_report(reeling and fish == 1, "E during the bite hooks it: %s" % _last_toast())
	await _wait(8)
	await _shot("08_fish_caught")
	# Too early: no fish.
	await _key(KEY_SPACE)
	await _wait(5)
	await _key(KEY_E)
	_report(not user.is_busy() and inventory.get_material_count(&"pond_perch") + inventory.get_material_count(&"silver_trout") + inventory.get_material_count(&"golden_carp") == fish,
			"pulling before the bite loses the fish (%s)" % _last_toast())


# --- woodcutting -----------------------------------------------------------------------

func _woodcutting() -> void:
	await _key(KEY_2)
	_report(inventory.get_equipped_tool().item_id == &"woodcutter_axe", "key 2 equips the Woodcutter's Axe (held model %s)" % _held_name())
	# The axe never attacks: Space at nothing says so, and spawns no bolt.
	player.teleport_to(Vector3(-20.0, 0, -12.0))
	await _wait(5)
	var bolts_before := level.find_children("*", "CombatProjectile", true, false).size()
	await _key(KEY_SPACE)
	_report(level.find_children("*", "CombatProjectile", true, false).size() == bolts_before and not user.is_busy(), "Space with the axe and no tree in reach: no attack (%s)" % _last_toast())
	for index in [1, 2]:
		var tree := level.get_node("ToolSites/GroveTree%d" % index) as HarvestNode
		player.teleport_to(tree.global_position + Vector3(1.2, 0, 1.2))
		_face(tree.global_position)
		rig.set_zoom(10.0)
		rig.snap_to_target()
		await _wait(15)
		var wood := inventory.get_material_count(&"wood")
		await _key(KEY_E)
		_report(user.state == ToolUser.State.WORKING, "E at %s starts chopping (prompt was '%s')" % [tree.name, tree.get_interaction_prompt(player)])
		if index == 1:
			await _until(func() -> bool: return not (user.get_progress().x < 2))
			await _wait(6)
			await _shot("09_chopping")
		await _until(func() -> bool: return not (user.is_busy()))
		_report(inventory.get_material_count(&"wood") > wood and not tree.is_available() and tree.depleted_visual.visible, "%s felled: %s, stump shown" % [tree.name, _last_toast()])
	await _wait(20)
	await _shot("10_tree_felled")


# --- mining and digging ----------------------------------------------------------------

func _mining_and_digging() -> void:
	await _key(KEY_3)
	var rock := level.get_node("ToolSites/QuarryRock1") as HarvestNode
	player.teleport_to(rock.global_position + Vector3(1.4, 0, 1.2))
	_face(rock.global_position)
	rig.set_zoom(10.0)
	rig.snap_to_target()
	await _wait(15)
	var stone := inventory.get_material_count(&"stone")
	await _key(KEY_E)
	await _until(func() -> bool: return not (user.get_progress().x < 2))
	await _wait(6)
	await _shot("11_mining")
	await _until(func() -> bool: return not (user.is_busy()))
	_report(inventory.get_material_count(&"stone") > stone, "mined %s with the Miner's Pickaxe (held %s): %s" % [rock.name, _held_name(), _last_toast()])
	for index in [2, 3]:
		var other := level.get_node("ToolSites/QuarryRock%d" % index) as HarvestNode
		player.teleport_to(other.global_position + Vector3(1.4, 0, 1.2))
		await _wait(5)
		await _key(KEY_E)
		await _until(func() -> bool: return not (user.is_busy()))
	_report(inventory.get_material_count(&"stone") >= 3, "three rocks mined: %d stone, %d iron ore" % [inventory.get_material_count(&"stone"), inventory.get_material_count(&"iron_ore")])
	await _key(KEY_4)
	var dig := level.get_node("ToolSites/WillowmerePond/DigWest") as HarvestNode
	player.teleport_to(dig.global_position + Vector3(0.8, 0, 1.0))
	_face(dig.global_position)
	rig.snap_to_target()
	await _wait(15)
	await _key(KEY_E)
	await _until(func() -> bool: return not (user.get_progress().x < 1))
	await _wait(4)
	await _shot("12_digging")
	await _until(func() -> bool: return not (user.is_busy()))
	_report(inventory.get_material_count(&"clay") > 0, "dug %s with the Shovel (held %s): %s" % [dig.name, _held_name(), _last_toast()])


# --- repairs and the jetty -------------------------------------------------------------

func _repair_and_jetty() -> void:
	# Hammer and trowel are on no quick slot (five slots, six tools): equip through Tab.
	var equipment := level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	await _key(KEY_TAB)
	equipment.activate_equip(&"carpenter_hammer")
	await _key(KEY_TAB)
	_report(inventory.get_equipped_tool().item_id == &"carpenter_hammer", "Equipment window equips the Carpenter's Hammer (held %s)" % _held_name())
	var jetty := level.get_node("ToolSites/WillowmerePond/Jetty") as RepairSite
	player.teleport_to(jetty.interactable.global_position + Vector3(0.5, 0, 0.5))
	_face(jetty.get_work_point())
	rig.set_zoom(11.0)
	rig.snap_to_target()
	await _wait(15)
	var wood := inventory.get_material_count(&"wood")
	var gold := CourierWallet.find(self).gold
	await _key(KEY_E)
	if not user.is_busy():
		_report(false, "jetty repair did not start: %s (wood %d)" % [_last_toast(), wood])
		return
	await _until(func() -> bool: return not (user.get_progress().x < 3))
	await _wait(4)
	await _shot("13_repairing_jetty")
	await _until(func() -> bool: return not (user.is_busy()))
	_report(jetty.is_repaired() and inventory.get_material_count(&"wood") == wood - 4 and CourierWallet.find(self).gold == gold + 30,
			"jetty repaired: %s (wood %d -> %d)" % [_last_toast(), wood, inventory.get_material_count(&"wood")])
	await _key(KEY_E)
	_report(not user.is_busy() and CourierWallet.find(self).gold == gold + 30, "a second E pays nothing (the jetty offers no repair any more)")
	# Walk out along the repaired jetty and fish from its end.
	await _key(KEY_1)
	var spot := level.get_node("ToolSites/WillowmerePond/JettySpot") as FishingSpot
	var walked := await _walk_until(spot.global_position, func() -> bool: return player.interaction.focused == spot.interactable, 500)
	_report(walked, "walked onto the repaired jetty to its fishing spot")
	user.bite_wait_min = 1.0
	user.bite_wait_max = 1.0
	await _wait(5)
	await _key(KEY_E)
	await _until(func() -> bool: return not (user.fish_state != ToolUser.FishState.WAITING))
	rig.snap_to_target()
	await _wait(20)
	await _shot("14_jetty_fishing")
	await _until(func() -> bool: return not (user.fish_state != ToolUser.FishState.BITE))
	await _key(KEY_E)
	await _until(func() -> bool: return not (user.is_busy()))
	_report(_last_toast().begins_with("Caught"), "fished from the jetty: %s" % _last_toast())
	# Trowel: the quarry wall needs 3 stone and 1 clay.
	await _key(KEY_TAB)
	equipment.activate_equip(&"mason_trowel")
	await _key(KEY_TAB)
	var wall := level.get_node("ToolSites/QuarryWall") as RepairSite
	player.teleport_to(wall.interactable.global_position + Vector3(0.3, 0, 0.6))
	_face(wall.get_work_point())
	await _wait(10)
	await _key(KEY_E)
	await _until(func() -> bool: return not (user.is_busy()))
	_report(wall.is_repaired(), "re-set the quarry wall with the Mason's Trowel: %s" % _last_toast())


# --- inventory and save ----------------------------------------------------------------

func _equipment() -> void:
	player.teleport_to(Vector3(-25.0, 0, -16.0))
	rig.set_zoom(14.0)
	rig.snap_to_target()
	await _wait(20)
	await _key(KEY_TAB)
	var equipment := level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	await _wait(10)
	# Scroll to the tools and materials.
	var scroll := equipment.item_list.get_parent() as ScrollContainer
	scroll.scroll_vertical = int(equipment.rows[&"fishing_rod"]["row"].position.y) - 40
	await _wait(5)
	_report(equipment.is_open() and equipment.material_rows.size() == 7, "Equipment window lists %d tools and %d materials" % [inventory.get_all_definitions().filter(func(i: ItemDefinition) -> bool: return i.is_tool()).size(), equipment.material_rows.size()])
	await _shot("15_equipment_tools")
	scroll.scroll_vertical = 100000
	await _wait(5)
	await _shot("16_equipment_materials")
	await _key(KEY_TAB)


func _save_and_reload() -> void:
	var save := SaveGame.find(self)
	var before := {
		"materials": inventory.get_material_counts(), "tool": inventory.get_equipped_tool().item_id,
		"owned": inventory.get_owned_ids().size(), "jetty": (level.get_node("ToolSites/WillowmerePond/Jetty") as RepairSite).is_repaired(),
		"tree": (level.get_node("ToolSites/GroveTree1") as HarvestNode).is_available(),
	}
	save.save_game()
	await _load_level()
	var after := {
		"materials": inventory.get_material_counts(), "tool": inventory.get_equipped_tool().item_id if inventory.get_equipped_tool() != null else &"",
		"owned": inventory.get_owned_ids().size(), "jetty": (level.get_node("ToolSites/WillowmerePond/Jetty") as RepairSite).is_repaired(),
		"tree": (level.get_node("ToolSites/GroveTree1") as HarvestNode).is_available(),
	}
	_report(str(before) == str(after), "save and reload keep tools, the tool in hand, materials, the repair and the felled tree: %s" % after)
	var spot := level.get_node("ToolSites/WillowmerePond/JettySpot") as FishingSpot
	_report(spot.interactable.enabled and not (level.get_node("ToolSites/WillowmerePond/Jetty/Blocker") as Node).can_process(), "after reload the jetty is walkable and its fishing spot open")


# --- helpers ---------------------------------------------------------------------------

func _report(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
	print("H5 %s %s" % ["ok  " if ok else "FAIL", text])


func _last_toast() -> String:
	var notifier := level.get_node("GameplayHUD/QuestNotification") as QuestNotification
	return notifier.history[notifier.history.size() - 1] if not notifier.history.is_empty() else ""


func _held_name() -> String:
	var character := player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	var held := character.get_held_item_node()
	return held.scene_file_path.get_file() if held != null else "none"


func _face(point: Vector3) -> void:
	var to := point - player.global_position
	player.facing.visual_root.rotation.y = FacingComponent.yaw_for_direction(to)


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await _wait(2)
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await _wait(2)


## Walks towards goal with the movement keys until done() or max_frames.
func _walk_until(goal: Vector3, done: Callable, max_frames: int) -> bool:
	var ok := false
	for i in max_frames:
		if done.call():
			ok = true
			break
		var to := goal - player.global_position
		to.y = 0.0
		if to.length() < 0.15:
			break
		var right := player.camera_relative_direction(Vector2.RIGHT)
		var back := player.camera_relative_direction(Vector2.DOWN)
		_press(&"move_right", &"move_left", to.normalized().dot(right))
		_press(&"move_back", &"move_forward", to.normalized().dot(back))
		await physics_frame
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right"]:
		Input.action_release(action)
	await _wait(3)
	return ok or done.call()


func _press(positive: StringName, negative: StringName, amount: float) -> void:
	Input.action_release(positive)
	Input.action_release(negative)
	if amount > 0.05:
		Input.action_press(positive, amount)
	elif amount < -0.05:
		Input.action_press(negative, -amount)


## Waits until done() (at most max_frames; a step that never finishes is reported by its check).
func _until(done: Callable, max_frames: int = 1500) -> void:
	for i in max_frames:
		if done.call():
			return
		await process_frame
	print("H5 (gave up waiting after %d frames)" % max_frames)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot_name + ".png")
	root.get_texture().get_image().save_png(path)
	print("H5 shot ", path)


func _delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
