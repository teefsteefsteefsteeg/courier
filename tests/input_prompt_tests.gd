extends SceneTree
## Pixel-art input prompt checks: cropped icons, InputMap lookups (including rebinding and
## keys without an icon), the reusable InputPrompt, "[Key]" label overlays, and in the
## real village the interaction prompt's world keycap (placement, hiding, HUD avoidance)
## and the HUD hint rows.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/input_prompt_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const ICON_DIR := "res://assets/ui/input_prompts/icons/"
const SHEET := "res://assets/ui/input_prompts/input_prompts.png"
## Every icon the crop tool writes (tools/crop_input_prompts.py).
const ICONS := [
	"key_w", "key_a", "key_s", "key_d", "key_q", "key_e", "key_r", "key_f", "key_g", "key_h", "key_j", "key_k", "key_l",
	"key_z", "key_x", "key_c", "key_v", "key_b", "key_n", "key_m",
	"key_1", "key_2", "key_3", "key_4", "key_5", "key_6",
	"key_up", "key_down", "key_left", "key_right",
	"key_tab", "key_shift", "key_ctrl", "key_alt", "key_esc",
	"key_f1", "key_f2", "key_f3", "key_f4", "key_f5", "key_f6", "key_f7", "key_f8", "key_f9", "key_f10", "key_f11", "key_f12",
	"key_space", "key_enter", "key_backspace", "key_delete", "key_insert", "key_home", "key_end", "key_page_up", "key_page_down",
	"mouse_left", "mouse_right", "mouse_middle", "mouse_wheel", "mouse_cursor", "mouse_hand",
]
## Gameplay actions whose bindings the HUD can show.
const ACTIONS := [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"run", &"interact", &"toggle_journal",
	&"toggle_map", &"drop_package", &"combat_magic_bolt", &"combat_dash", &"package_shield",
	&"toggle_debug_hud", &"zoom_in", &"zoom_out", &"ui_cancel",
]

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var prompt: InteractionPrompt
var dialogue: DialogueBox
var journal: QuestJournal
var hud: GameplayHUD


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_icons()
	_test_bindings()
	await _test_rebinding_and_fallback()
	_test_parse()

	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	prompt = level.get_node("InteractionPrompt")
	dialogue = level.get_node("DialogueBox")
	journal = level.get_node("QuestJournal")
	hud = level.get_node("GameplayHUD")
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	await _frames(20)

	await _test_hud_hints()
	await _test_world_badge()
	await _test_badge_hides()
	await _test_badge_avoids_hud()
	await _test_rebind_in_village()
	await _test_movement_guide()
	await _test_package_hint()

	print("\n=== Input prompt tests: %d passed, %d failed ===" % [_passes, _failures])
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
		await physics_frame
	await process_frame
	await process_frame


func _icon_name(control: Control) -> String:
	var rect := control as TextureRect
	return rect.texture.resource_path.get_file().get_basename() if rect != null and rect.texture != null else ""


func _overlay_keys(label: Label) -> PackedStringArray:
	var overlay := label.get_node_or_null(NodePath(InputPromptLabel.NODE_NAME)) as InputPromptLabel
	var keys: PackedStringArray = []
	if overlay != null:
		for keycap in overlay.keycaps:
			keys.append(_icon_name(keycap) if keycap is TextureRect else "fallback:" + str(keycap.get_meta(&"key", "")))
	return keys


func _stand_near(target: Node3D, toward: Vector3, distance: float = 1.3) -> void:
	var offset := toward - target.global_position
	offset.y = 0.0
	player.teleport_to(target.global_position + offset.normalized() * distance)
	rig.snap_to_target()
	await _frames(8)


func _rebind(action: StringName, keycode: Key) -> Array[InputEvent]:
	var old := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
	return old


func _restore(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for event in events:
		InputMap.action_add_event(action, event)


# --- icons and bindings ------------------------------------------------------

func _test_icons() -> void:
	print("[Cropped icons]")
	var missing: PackedStringArray = []
	var wrong_height: PackedStringArray = []
	var mipmapped: PackedStringArray = []
	for icon_name in ICONS:
		var texture := load(ICON_DIR + icon_name + ".png") as Texture2D
		if texture == null:
			missing.append(icon_name)
			continue
		if texture.get_height() != 32:
			wrong_height.append("%s:%d" % [icon_name, texture.get_height()])
		if texture.get_image().has_mipmaps():
			mipmapped.append(icon_name)
	_check(missing.is_empty(), "all %d icons load %s" % [ICONS.size(), missing])
	_check(wrong_height.is_empty(), "icons are 32 px tall for 1:1 display %s" % wrong_height)
	_check(mipmapped.is_empty(), "icons import without mipmaps %s" % mipmapped)
	var sheet := load(SHEET) as Texture2D
	var widest := 0
	for icon_name in ICONS:
		widest = maxi(widest, (load(ICON_DIR + icon_name + ".png") as Texture2D).get_width())
	_check(sheet != null and widest < sheet.get_width() / 8, "icons are single crops, never the whole sheet (widest %d px)" % widest)
	var single := (load(ICON_DIR + "key_e.png") as Texture2D).get_size()
	_check(single.x <= 40 and single.y == 32, "a letter key is one keycap (%s)" % single)


func _test_bindings() -> void:
	print("[Bindings read from the InputMap]")
	var unresolved: PackedStringArray = []
	for action in ACTIONS:
		if InputPromptIcons.texture_for_action(action) == null:
			unresolved.append(action)
	_check(unresolved.is_empty(), "every gameplay binding has an icon %s" % unresolved)
	# Expected icons are derived from the project's own InputMap, not assumed.
	for action in [&"move_forward", &"interact", &"toggle_journal", &"combat_magic_bolt", &"run"]:
		var event := InputPromptIcons.primary_event(action) as InputEventKey
		var key_name := OS.get_keycode_string(event.physical_keycode).to_lower()
		var expected: String = InputPromptIcons.SPECIAL_KEYS.get(event.physical_keycode, "key_" + key_name)
		var texture := InputPromptIcons.texture_for_action(action)
		_check(texture != null and texture.resource_path.get_file().get_basename() == expected,
				"%s (%s) shows %s" % [action, OS.get_keycode_string(event.physical_keycode), expected])
	_check(InputPromptIcons.texture_for_action(&"zoom_in").resource_path.ends_with("mouse_wheel.png"), "zoom_in shows the mouse wheel (it also has a key without an icon)")
	_check(InputPromptIcons.texture_for_action(&"no_such_action") == null and InputPromptIcons.primary_event(&"no_such_action") == null, "unknown action resolves to nothing")
	_check(InputPromptIcons.texture_for_key(KEY_T) == null and InputPromptIcons.texture_for_key(KEY_0) == null, "keys missing from the sheet have no icon (T, 0)")


func _test_rebinding_and_fallback() -> void:
	print("[InputPrompt component: rebinding and fallback keycaps]")
	var component := InputPrompt.new()
	component.actions = [&"move_forward", &"move_left", &"move_back", &"move_right"]
	component.text = "Move"
	root.add_child(component)
	await process_frame
	var names: PackedStringArray = []
	for keycap in component.keycaps:
		names.append(_icon_name(keycap))
	_check(names == PackedStringArray(["key_w", "key_a", "key_s", "key_d"]), "movement prompt follows the bound keys %s" % names)
	_check(component.text_label != null and component.text_label.text == "Move", "prompt text shown")
	_check(component.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and (component.keycaps[0] as TextureRect).texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "keycaps use nearest filtering")
	_check(is_equal_approx(component.keycaps[0].custom_minimum_size.y, 32.0), "keycaps draw 1:1")

	var old := _rebind(&"move_forward", KEY_UP)
	component.refresh()
	_check(_icon_name(component.keycaps[0]) == "key_up", "rebinding move_forward to Up shows the arrow key")
	_restore(&"move_forward", old)
	old = _rebind(&"move_forward", KEY_T)
	component.refresh()
	var fallback := component.keycaps[0]
	_check(fallback is PanelContainer and (fallback.get_child(0) as Label).text == "T", "a key without an icon gets a drawn keycap 'T'")
	_restore(&"move_forward", old)
	component.actions = [&"no_such_action"]
	component.refresh()
	_check(component.keycaps[0] is PanelContainer and (component.keycaps[0].get_child(0) as Label).text == "?", "an unbound action shows '?'")
	component.icon_scale = 2
	component.actions = [&"interact"]
	component.refresh()
	_check(is_equal_approx(component.keycaps[0].custom_minimum_size.y, 64.0), "integer icon scale (2x = 64 px)")
	component.queue_free()

	var scene := (load("res://scenes/ui/input_prompt.tscn") as PackedScene).instantiate() as InputPrompt
	root.add_child(scene)
	await process_frame
	_check(scene.keycaps.size() == 1 and _icon_name(scene.keycaps[0]) == "key_e" and scene.text_label.text == "Interact", "input_prompt.tscn shows [E] Interact")
	scene.queue_free()


func _test_parse() -> void:
	print("[Hint text parsing]")
	var lines := InputPromptLabel.parse("[E] Talk   [Escape] Close")
	_check(lines.size() == 1 and lines[0].size() == 4, "one line, four segments (%s)" % [lines])
	_check(lines[0][0] == {"key": "E"} and lines[0][1]["text"] == "Talk" and lines[0][1]["gap"] and lines[0][2] == {"key": "Escape"}, "keys, text and the group gap")
	lines = InputPromptLabel.parse("Reward [not a key] and [?] Journal\n[F3] Debug")
	_check(lines.size() == 2 and lines[0][0]["text"] == "Reward [not a key] and" and lines[0][1] == {"key": "?"}, "non-key brackets stay text; '?' is an unbound key")
	_check(lines[1][0] == {"key": "F3"}, "second line parsed")


# --- village -------------------------------------------------------------------

func _test_hud_hints() -> void:
	print("[HUD hints use keycaps]")
	var onboarding := hud.onboarding
	# Journal and map keys moved to the keyboard guide (keycaps only, no labels).
	_check(_overlay_keys(onboarding) == PackedStringArray(["key_e"]), "onboarding hints: %s" % _overlay_keys(onboarding))
	_check(onboarding.self_modulate.a == 0.0, "onboarding's own text is replaced by the keycap row")
	_check(journal.hint_label.text == "[J] Journal" and _overlay_keys(journal.hint_label) == PackedStringArray(["key_j"]), "journal hint keeps its text and shows J")
	_check(_overlay_keys(journal.close_hint) == PackedStringArray(["key_j"]), "journal close hint shows J")
	var map := hud.get_node("Minimap")
	# Phase 8 world map: zoom (= -), pan (W A S D), close (M / Esc).
	_check(_overlay_keys(map.expanded_hint) == PackedStringArray(["fallback:Equal", "fallback:Minus", "key_w", "key_a", "key_s", "key_d", "key_m", "key_esc"]), "map hint: %s" % _overlay_keys(map.expanded_hint))

	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	await _stand_near(bram, bram.global_position + Vector3(0, 0, 1.4))
	_check(prompt.panel.visible and prompt.label.text == "[E] Talk to Postmaster Bram", "prompt keeps its text '%s'" % prompt.label.text)
	_check(_overlay_keys(prompt.label) == PackedStringArray(["key_e"]) and prompt.label_overlay.is_active(), "prompt line draws the E keycap")
	bram.interactable.interact(player)
	await _frames(2)
	_check(dialogue.is_open() and _overlay_keys(dialogue.hint_label).size() >= 1, "dialogue hint draws keycaps %s" % _overlay_keys(dialogue.hint_label))
	_check(not journal.hint_label.visible, "journal hint stands down under the dialogue box")
	dialogue.skip_typing()
	await _frames(1)
	_check(_overlay_keys(dialogue.hint_label) == PackedStringArray(["key_e", "key_esc"]), "dialogue 'Talk / Close' hint: %s" % _overlay_keys(dialogue.hint_label))
	_check(not dialogue.hint_label.get_global_rect().intersects(journal.hint_label.get_global_rect()) or not journal.hint_label.visible, "dialogue hint and journal hint never overlap")
	dialogue.close()
	await _frames(1)
	_check(journal.hint_label.visible, "journal hint returns after the dialogue")


func _test_world_badge() -> void:
	print("[World keycap beside the focused object]")
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	await _stand_near(bram, bram.global_position + Vector3(0, 0, 1.4))
	var badge := prompt.world_badge
	_check(player.interaction.focused == bram.interactable and badge.visible, "badge shows while Bram is focused")
	_check(badge.keycaps.size() == 1 and _icon_name(badge.keycaps[0]) == "key_e", "badge shows the interact binding")
	var camera := get_root().get_viewport().get_camera_3d()
	var anchor := camera.unproject_position(prompt.get_badge_anchor(bram.interactable))
	var badge_rect := badge.get_global_rect()
	_check(badge_rect.has_point(anchor + prompt.badge_offset + Vector2(4, 0)) or badge_rect.position.distance_to(anchor) < 60.0, "badge sits beside Bram's head (anchor %s, badge %s)" % [anchor, badge_rect])
	_check(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(badge_rect), "badge on screen")
	_check(not badge_rect.intersects(prompt.panel.get_global_rect()), "badge clear of the prompt line")
	var hits: PackedStringArray = []
	for node in get_nodes_in_group(InputPrompt.AVOID_GROUP):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().intersects(badge_rect):
			hits.append(control.name)
	_check(hits.is_empty(), "badge clear of the HUD %s" % hits)
	_check(get_nodes_in_group(InputPrompt.AVOID_GROUP).size() >= 8, "tracker, wallet, minimap, dialogue and package panels are avoided (%d)" % get_nodes_in_group(InputPrompt.AVOID_GROUP).size())

	var board := level.get_node("PostOffice/Markers/QuestBoardSpot/QuestBoard") as Node3D
	await _stand_near(board, board.global_position + Vector3(0, 0, 2))
	# Objects use the object anchor height unless they set their own: the Phase 7 guild board
	# is taller than the old one, so its badge sits at the board's "prompt_anchor_height".
	var expected_height := float(prompt._focused.get_meta(&"prompt_anchor_height", prompt.object_badge_height))
	_check(badge.visible and is_equal_approx(prompt.get_badge_anchor(prompt._focused).y - prompt._focused.get_parent().global_position.y, expected_height), "objects use their anchor height (%.1f m)" % expected_height)


func _test_badge_hides() -> void:
	print("[Badge hides when interaction is unavailable]")
	var badge := prompt.world_badge
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	await _stand_near(bram, bram.global_position + Vector3(0, 0, 1.4))
	_check(badge.visible, "badge visible near Bram")
	player.teleport_to(Vector3(0, 0, 4))
	rig.snap_to_target()
	await _frames(8)
	_check(player.interaction.focused == null and not badge.visible and not prompt.panel.visible, "nothing in range: no badge")

	await _stand_near(bram, bram.global_position + Vector3(0, 0, 1.4))
	bram.interactable.interact(player)
	await _frames(1)
	_check(dialogue.is_open() and not badge.visible, "dialogue open: no badge")
	dialogue.close()
	await _frames(1)
	_check(badge.visible, "badge back after the dialogue")
	journal.open()
	await _frames(1)
	_check(not badge.is_visible_in_tree(), "journal open: no badge")
	journal.close()
	await _frames(1)
	hud.get_node("Minimap").set_expanded(true)
	await _frames(1)
	_check(not badge.visible, "expanded map open: no badge")
	hud.get_node("Minimap").set_expanded(false)
	await _frames(2)
	_check(badge.visible, "badge back after the map")
	bram.interactable.enabled = false
	await _frames(2)
	_check(not badge.visible and not prompt.panel.visible, "disabled interactable: no badge")
	bram.interactable.enabled = true
	await _frames(2)
	_check(badge.visible, "re-enabled: badge back")


func _test_badge_avoids_hud() -> void:
	print("[Badge avoids HUD panels]")
	var badge := prompt.world_badge
	_check(badge.visible, "badge visible before a panel covers it")
	var blocker := Control.new()
	# Generous margin: the camera may still settle a few pixels between frames.
	blocker.position = badge.position - Vector2(80, 80)
	blocker.size = badge.size + Vector2(160, 160)
	blocker.add_to_group(InputPrompt.AVOID_GROUP)
	hud.add_child(blocker)
	await _frames(1)
	_check(not badge.visible and prompt.panel.visible, "a HUD panel under the badge hides it (the prompt line stays)")
	blocker.queue_free()
	await _frames(2)
	_check(badge.visible, "badge returns once the panel is gone")


func _test_rebind_in_village() -> void:
	print("[Rebinding updates the prompts]")
	var old := _rebind(&"interact", KEY_F)
	prompt.world_badge.refresh()
	prompt._refresh()
	await _frames(2)
	_check(prompt.label.text.begins_with("[F] "), "prompt text follows the new binding '%s'" % prompt.label.text)
	_check(_overlay_keys(prompt.label) == PackedStringArray(["key_f"]) and _icon_name(prompt.world_badge.keycaps[0]) == "key_f", "both keycaps show F")
	_restore(&"interact", old)
	prompt.world_badge.refresh()
	prompt._refresh()
	await _frames(2)
	_check(_overlay_keys(prompt.label) == PackedStringArray(["key_e"]), "restored to E")


func _test_movement_guide() -> void:
	print("[Movement guide]")
	UISettings.persist = false
	var guide := hud.movement_guide
	await _frames(2)
	_check(guide != null and guide.is_visible_in_tree(), "movement guide shown in the HUD")
	var shown: PackedStringArray = []
	var expected: PackedStringArray = []
	for action in MovementGuide.ACTIONS:
		shown.append(_icon_name(guide.keycaps[action]))
		var event := InputPromptIcons.primary_event(action) as InputEventKey
		expected.append("key_" + OS.get_keycode_string(event.physical_keycode).to_lower())
	_check(shown == expected, "guide keys follow the InputMap %s" % shown)
	_check(shown == PackedStringArray(["key_w", "key_a", "key_s", "key_d"]), "this project's movement keys are W A S D")
	var w := guide.keycaps[MovementGuide.FORWARD].get_global_rect()
	var s_key := guide.keycaps[MovementGuide.BACK].get_global_rect()
	_check(w.end.y <= s_key.position.y and absf(w.get_center().x - s_key.get_center().x) < 2.0, "forward sits above back (inverted T)")
	_check(guide.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "guide keycaps use nearest filtering")

	var old := _rebind(&"move_forward", KEY_UP)
	await create_timer(MovementGuide.BINDING_CHECK_INTERVAL + 0.1).timeout
	await _frames(1)
	_check(_icon_name(guide.keycaps[MovementGuide.FORWARD]) == "key_up", "rebinding forward to Up updates the guide by itself")
	_restore(&"move_forward", old)
	guide.refresh()

	UISettings.set_value(UISettings.SHOW_MOVEMENT_GUIDE, false)
	await _frames(1)
	_check(not guide.visible, "UI setting hides the guide")
	UISettings.set_value(UISettings.SHOW_MOVEMENT_GUIDE, true)
	await _frames(1)
	_check(guide.visible, "UI setting shows it again")

	for canvas in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 600)]:
		root.size = canvas
		root.content_scale_size = canvas
		await _frames(3)
		var rect := guide.get_global_rect()
		var hits: PackedStringArray = []
		var others: Array[Control] = [prompt.panel, journal.hint_label, hud.get_node("Minimap").compact]
		for node in get_nodes_in_group(InputPrompt.AVOID_GROUP):
			others.append(node as Control)
		var combat := hud._combat_panel
		if combat != null:
			others.append(combat)
		for control in others:
			if control != guide and control.is_visible_in_tree() and control.get_global_rect().intersects(rect):
				hits.append(control.name)
		_check(guide.visible and Rect2(Vector2.ZERO, Vector2(canvas)).encloses(rect) and hits.is_empty(),
				"guide on screen and clear of the HUD at %s (rect %s, overlaps %s)" % [canvas, rect, hits])
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	await _frames(2)


## Last: picking up posts a toast, and the toast panel (correctly) hides any badge under it.
func _test_package_hint() -> void:
	print("[Package hint]")
	var carrier := PackageCarrier.find_on(player)
	carrier.pick_up(PackageInstance.new(load("res://data/packages/pkg_ordinary_parcel.tres")))
	await _frames(1)
	_check(hud.package_indicator.visible and hud.package_indicator.hint_label.text == "[G] Drop", "package hint text '%s'" % hud.package_indicator.hint_label.text)
	_check(_overlay_keys(hud.package_indicator.hint_label) == PackedStringArray(["key_g"]), "package hint draws the drop binding (G)")
	carrier.remove_package(&"test")
