extends SceneTree
## HUD keyboard guide (MovementGuide + AnimatedKeycap) in the real village: keycaps only (no
## descriptive labels), keys from the InputMap, W pressed while held, W + D and W + A
## together, release restores the raised pose, a same-frame tap shows and does not stick,
## and the guide never takes input away from the courier.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/keycap_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const EXPECTED := [&"move_forward", &"move_left", &"move_back", &"move_right", &"interact", &"package_shield",
		&"toggle_map", &"toggle_journal", &"toggle_equipment", &"run", &"combat_magic_bolt"]

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var guide: MovementGuide


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	await _frames(20)
	guide = (level.get_node("GameplayHUD") as GameplayHUD).movement_guide
	_test_layout()
	await _test_presses()
	await _test_tap()
	await _test_gameplay_untouched()
	print("\n=== Keycap tests: %d passed, %d failed ===" % [_passes, _failures])
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
		await process_frame


func _key(action: StringName) -> AnimatedKeycap:
	return guide.animated[action]


func _test_layout() -> void:
	print("[Layout]")
	var missing := EXPECTED.filter(func(action: StringName) -> bool: return not guide.animated.has(action))
	_check(missing.is_empty(), "every configured control has a keycap (%s missing)" % [missing])
	var texts: Array[String] = []
	for label in guide.find_children("*", "Label", true, false):
		if not (label as Label).text.is_empty() and not guide.animated.values().any(func(k: AnimatedKeycap) -> bool: return k.is_ancestor_of(label)):
			texts.append((label as Label).text)
	_check(texts.is_empty(), "no descriptive labels like Move / Map / Journal (%s)" % [texts])
	var icons: Array[String] = []
	for action in [&"move_forward", &"move_left", &"move_back", &"move_right", &"toggle_map", &"toggle_journal", &"interact"]:
		var face := guide.keycaps[action] as TextureRect
		icons.append(face.texture.resource_path.get_file().get_basename() if face != null else "?")
	_check(icons == ["key_w", "key_a", "key_s", "key_d", "key_m", "key_j", "key_e"], "keys follow the InputMap %s" % [icons])
	var w := _key(&"move_forward").get_global_rect()
	var s := _key(&"move_back").get_global_rect()
	var a := _key(&"move_left").get_global_rect()
	var d := _key(&"move_right").get_global_rect()
	_check(w.end.y <= s.position.y + 1.0 and absf(w.get_center().x - s.get_center().x) < 2.0 and a.end.x <= s.position.x and s.end.x <= d.position.x,
			"W above S, with A S D in a row (inverted T)")


func _test_presses() -> void:
	print("[Holding keys]")
	var w := _key(&"move_forward")
	var d := _key(&"move_right")
	var a := _key(&"move_left")
	_check(not w.pressed and is_equal_approx(w.face.position.y, 0.0), "W starts raised")
	player.input_enabled = false
	Input.action_press(&"move_forward")
	await _frames(3)
	_check(w.pressed and is_equal_approx(w.face.position.y, AnimatedKeycap.PRESS_DEPTH) and w.face.modulate.r < 0.9, "W held: face down %d px and darker" % AnimatedKeycap.PRESS_DEPTH)
	await _frames(20)
	_check(w.pressed and is_equal_approx(w.face.position.y, AnimatedKeycap.PRESS_DEPTH), "W stays down while held")
	Input.action_press(&"move_right")
	await _frames(3)
	_check(w.pressed and d.pressed and not a.pressed, "W + D pressed together, A raised")
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await _frames(3)
	_check(w.pressed and a.pressed, "W + A pressed together")
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	await _until(func() -> bool: return is_equal_approx(w.face.position.y, 0.0) and is_equal_approx(a.face.position.y, 0.0), 1.0)
	_check(not w.pressed and not a.pressed and is_equal_approx(w.face.position.y, 0.0) and w.face.modulate == Color.WHITE, "releasing restores the raised keycaps")
	player.input_enabled = true


func _test_tap() -> void:
	print("[Short tap]")
	var m := _key(&"toggle_map")
	var down := InputEventKey.new()
	down.physical_keycode = KEY_M
	down.keycode = KEY_M
	down.pressed = true
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	# Press and release inside one frame: the tap must still show, then clear.
	Input.parse_input_event(down)
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await _frames(1)
	_check(m.pressed, "a same-frame tap still shows M pressed")
	await _until(func() -> bool: return not m.pressed, 1.0)
	_check(not m.pressed, "and it does not stay stuck")
	# Close the map the tap opened.
	Input.parse_input_event(down)
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await _frames(3)


func _test_gameplay_untouched() -> void:
	print("[Gameplay keeps its input]")
	var start := player.global_position
	Input.action_press(&"move_right")
	await _frames(30)
	Input.action_release(&"move_right")
	_check(player.global_position.distance_to(start) > 0.5, "holding D still moves the courier (%.1f m)" % player.global_position.distance_to(start))
	var journal := level.get_node("QuestJournal") as QuestJournal
	var down := InputEventKey.new()
	down.physical_keycode = KEY_J
	down.keycode = KEY_J
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await _frames(2)
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await _frames(2)
	_check(journal.is_open(), "J still opens the journal")
	journal.close()


func _until(condition: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < end:
		await process_frame
