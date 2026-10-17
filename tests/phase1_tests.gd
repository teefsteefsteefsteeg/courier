extends SceneTree
## Phase 1 automated checks. Run headless from the project root:
##   godot --headless --path . --script res://tests/phase1_tests.gd
## Exit code = number of failed checks.

const MAIN_SCENE := "res://scenes/levels/test_yard.tscn"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_input_map()

	level = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _frames(20)

	_test_camera_setup()
	await _test_eight_directions()
	await _test_acceleration_and_run()
	await _test_deceleration_and_idle()
	await _test_facing()
	await _test_direction_stable_while_camera_follows()
	await _test_collision()
	await _test_interaction_range()
	await _test_zoom_bounds()

	print("\n=== Phase 1 tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"run"]:
		Input.action_release(action)


func _cam_forward() -> Vector3:
	var b := rig.camera.global_basis
	return Vector3(-b.z.x, 0.0, -b.z.z).normalized()


func _cam_right() -> Vector3:
	var b := rig.camera.global_basis
	return Vector3(b.x.x, 0.0, b.x.z).normalized()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _reset_player(at: Vector3 = Vector3.ZERO) -> void:
	_release_all()
	player.teleport_to(at)
	rig.snap_to_target()


# --- tests -------------------------------------------------------------------

func _test_input_map() -> void:
	print("[Input Map]")
	var expected := {
		&"move_forward": KEY_W, &"move_back": KEY_S, &"move_left": KEY_A,
		&"move_right": KEY_D, &"run": KEY_SHIFT, &"interact": KEY_E, &"toggle_debug_hud": KEY_F3,
	}
	for action in expected:
		var found := false
		if InputMap.has_action(action):
			for e in InputMap.action_get_events(action):
				if e is InputEventKey and (e as InputEventKey).physical_keycode == expected[action]:
					found = true
		_check(found, "%s bound to %s" % [action, OS.get_keycode_string(expected[action])])
	_check(InputMap.has_action(&"zoom_in") and InputMap.has_action(&"zoom_out"), "zoom actions exist")


func _test_camera_setup() -> void:
	print("[Camera]")
	_check(rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "camera is orthographic")
	_check(root.get_viewport().get_camera_3d() == rig.camera, "rig camera is the active camera")
	var rot := rig.camera.global_rotation_degrees
	_check(is_equal_approx(snappedf(rot.y, 0.01), 45.0), "yaw ~45 deg (got %.2f)" % rot.y)
	_check(is_equal_approx(snappedf(rot.x, 0.01), -35.0), "pitch ~-35 deg (got %.2f)" % rot.x)
	var postmaster := level.get_node("NPCs/Postmaster") as Node3D
	_check(absf(postmaster.global_rotation_degrees.y - (-135.0)) < 0.5, "scene transforms load as authored (Postmaster yaw %.1f)" % postmaster.global_rotation_degrees.y)


func _test_eight_directions() -> void:
	print("[8-direction camera-relative movement]")
	var f := _cam_forward()
	var r := _cam_right()
	var cases := [
		[[&"move_forward"], f, "W"], [[&"move_back"], -f, "S"],
		[[&"move_right"], r, "D"], [[&"move_left"], -r, "A"],
		[[&"move_forward", &"move_right"], (f + r).normalized(), "W+D"],
		[[&"move_forward", &"move_left"], (f - r).normalized(), "W+A"],
		[[&"move_back", &"move_right"], (-f + r).normalized(), "S+D"],
		[[&"move_back", &"move_left"], (-f - r).normalized(), "S+A"],
	]
	for c in cases:
		_reset_player()
		await _frames(3)
		var start := player.global_position
		for a in c[0]:
			Input.action_press(a)
		await _frames(30)
		var moved := _flat(player.global_position - start)
		_release_all()
		var dot := moved.normalized().dot(c[1])
		_check(moved.length() > 1.0 and dot > 0.995, "%s moves along expected camera-relative dir (dot=%.4f, dist=%.2f)" % [c[2], dot, moved.length()])


func _test_acceleration_and_run() -> void:
	print("[Acceleration / run]")
	_reset_player()
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(1)
	var speed_first := player.get_horizontal_speed()
	await _frames(40)
	var walk_speed := player.get_horizontal_speed()
	_check(speed_first > 0.0 and speed_first < walk_speed * 0.5, "accelerates gradually (frame1 %.2f -> %.2f)" % [speed_first, walk_speed])
	_check(absf(walk_speed - player.movement.walk_speed) < 0.05, "reaches walk speed %.2f" % walk_speed)
	_check(player.movement.get_state_name() == "WALK", "state WALK while walking (got %s)" % player.movement.get_state_name())
	Input.action_press(&"run")
	await _frames(40)
	var run_speed := player.get_horizontal_speed()
	_check(absf(run_speed - player.movement.run_speed) < 0.05, "reaches run speed %.2f with Shift" % run_speed)
	_check(player.movement.get_state_name() == "RUN", "state RUN while running (got %s)" % player.movement.get_state_name())
	_release_all()


func _test_deceleration_and_idle() -> void:
	print("[Deceleration]")
	_reset_player()
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(40)
	_release_all()
	await _frames(1)
	var after_one := player.get_horizontal_speed()
	_check(after_one > 0.0, "does not stop instantly (%.2f m/s after 1 frame)" % after_one)
	await _frames(30)
	_check(player.get_horizontal_speed() < 0.01, "comes to rest")
	_check(player.movement.get_state_name() == "IDLE", "state IDLE at rest (got %s)" % player.movement.get_state_name())


func _test_facing() -> void:
	print("[Facing]")
	_reset_player()
	await _frames(3)
	Input.action_press(&"move_right")
	await _frames(2)
	var partial := player.facing.get_facing_direction().dot(_cam_right())
	await _frames(40)
	var full := player.facing.get_facing_direction().dot(_cam_right())
	_release_all()
	_check(partial < 0.999, "rotation is smoothed, not snapped (dot after 2 frames %.3f)" % partial)
	_check(full > 0.999, "ends facing move direction (dot %.4f)" % full)
	_check(player.global_basis.z.is_equal_approx(Vector3.BACK), "physics body itself is not rotated")


func _test_direction_stable_while_camera_follows() -> void:
	print("[Camera follow stability]")
	_reset_player()
	await _frames(3)
	var rig_start := rig.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"move_left")
	var first_dir := Vector3.ZERO
	var max_dev := 0.0
	for i in 60:
		await physics_frame
		await process_frame
		if first_dir == Vector3.ZERO:
			first_dir = player.move_direction
		max_dev = maxf(max_dev, first_dir.angle_to(player.move_direction))
	_release_all()
	_check(rig.global_position.distance_to(rig_start) > 1.0, "camera follows player (moved %.2f m)" % rig.global_position.distance_to(rig_start))
	_check(max_dev < 0.0001, "move direction constant while camera moves (max deviation %.6f rad)" % max_dev)
	var lag := _flat(rig.global_position - rig.focus_offset - player.global_position).length()
	_check(lag > 0.01, "follow is smoothed (lag %.2f m)" % lag)


func _test_collision() -> void:
	print("[Collision]")
	# Crate A: axis-aligned 1x1x1 box at (6,0,3); west face at x = 5.5.
	# Push head-on along world +X (= S+D for this camera) so there is no slide-around.
	var crate := level.get_node("Props/CrateA") as Node3D
	var approach := _cam_forward()
	_reset_player(crate.global_position + Vector3(-3, 0, 0))
	await _frames(3)
	Input.action_press(&"move_back")
	Input.action_press(&"move_right")
	var hit_crate := false
	for i in 120:
		await physics_frame
		for c in player.get_slide_collision_count():
			if player.get_slide_collision(c).get_collider() == crate:
				hit_crate = true
	_release_all()
	var face_x := crate.global_position.x - 0.5
	_check(hit_crate, "player collides with crate")
	_check(player.global_position.x < face_x - 0.3, "player does not penetrate crate (x=%.3f, face=%.2f)" % [player.global_position.x, face_x])
	_check(absf(player.global_position.z - crate.global_position.z) < 0.05, "head-on push does not drift sideways")

	# Boundary fence at z = -18.
	_reset_player(Vector3(0, 0, -15))
	await _frames(3)
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")  # forward+right = world -Z
	Input.action_press(&"run")
	await _frames(120)
	_release_all()
	_check(player.global_position.z > -18.0 + 0.35 - 0.05, "player stopped by north fence (z=%.2f)" % player.global_position.z)

	# NPC body blocks the player too.
	var npc := level.get_node("NPCs/Postmaster") as Node3D
	_reset_player(npc.global_position - approach * 3.0)
	await _frames(3)
	Input.action_press(&"move_forward")
	await _frames(120)
	_release_all()
	var to_npc := _flat(npc.global_position - player.global_position).length()
	_check(to_npc > 0.7, "player blocked by NPC body (distance %.2f)" % to_npc)


func _test_interaction_range() -> void:
	print("[Interaction]")
	var npc := level.get_node("NPCs/Postmaster") as NPC
	var detector := player.interaction

	_reset_player(npc.global_position + Vector3(6, 0, 0))
	await _frames(5)
	_check(detector.focused == null, "no focus when 6 m away")
	var before := npc.interaction_count
	_press_interact()
	await _frames(3)
	_check(npc.interaction_count == before, "E out of range does nothing")

	_reset_player(npc.global_position + Vector3(2.5, 0, 0))
	await _frames(5)
	_check(detector.focused == null, "no focus at 2.5 m (just outside range)")

	_reset_player(npc.global_position + Vector3(1.5, 0, 0))
	await _frames(5)
	_check(detector.focused == npc.interactable, "focus acquired at 1.5 m")
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	_check(prompt.panel.visible and prompt.label.text == "[E] Talk to Postmaster Bram", "prompt shows '%s'" % prompt.label.text)
	_press_interact()
	await _frames(3)
	_check(npc.interaction_count == before + 1, "E in range triggers interaction")
	_check(npc.speech_label.visible and npc.speech_label.text == npc.lines[0], "NPC shows first line")
	await _frames(30)
	var to_player := _flat(player.global_position - npc.global_position).normalized()
	var npc_facing := -npc.visual.global_basis.z
	_check(_flat(npc_facing).normalized().dot(to_player) > 0.95, "NPC turns to face player")

	_reset_player(npc.global_position + Vector3(6, 0, 0))
	await _frames(5)
	_check(detector.focused == null and not prompt.panel.visible, "focus and prompt clear after leaving")


func _press_interact() -> void:
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = &"interact"
	up.pressed = false
	Input.parse_input_event(up)


func _test_zoom_bounds() -> void:
	print("[Zoom]")
	for i in 30:
		rig.set_zoom(rig.target_zoom_size + rig.zoom_step)
	_check(is_equal_approx(rig.target_zoom_size, rig.max_zoom_size), "zoom out clamps to max %.1f" % rig.target_zoom_size)
	for i in 30:
		var ev := InputEventAction.new()
		ev.action = &"zoom_in"
		ev.pressed = true
		Input.parse_input_event(ev)
	await _frames(5)
	_check(is_equal_approx(rig.target_zoom_size, rig.min_zoom_size), "zoom_in action clamps to min %.1f" % rig.target_zoom_size)
	for i in 120:
		await process_frame
	_check(absf(rig.camera.size - rig.min_zoom_size) < 0.05, "camera size eases to target (%.2f)" % rig.camera.size)
	rig.set_zoom(rig.zoom_size)
