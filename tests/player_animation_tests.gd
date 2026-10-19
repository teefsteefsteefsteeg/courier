extends SceneTree
## Courier animation state checks in the real village, driven by Input actions and
## physics frames: run/idle transitions, and the dash one-shot ending with the dash
## (released keys -> idle, held keys -> run, repeated dashes, a dash into a wall, a
## knockout during a dash, a magic bolt during a dash). Regression for the dash pose
## (a looping run clip) never ending and keeping the courier running in place.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/player_animation_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const OPEN_GROUND := Vector3(0, 0, 4)
const MOVE := [&"move_forward", &"move_back", &"move_left", &"move_right", &"run"]

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var combat: CombatController
var character: KayKitCharacter
var idle_clip: StringName
var walk_clip: StringName
var run_clip: StringName
var dash_clip: StringName


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	combat = player.get_node("Combat") as CombatController
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	idle_clip = character.resolve(&"idle")
	walk_clip = character.resolve(&"walk")
	run_clip = character.resolve(&"run")
	dash_clip = character.resolve(&"dash")
	await _frames(30)

	_test_clip_setup()
	await _test_looping_one_shot_ends()
	await _test_run_release_idle()
	await _test_dash_release_idle()
	await _test_dash_hold_run()
	await _test_repeated_dashes()
	await _test_dash_into_wall()
	await _test_bolt_during_dash()
	await _test_knockout_during_dash()

	_release_all()
	print("\n=== Player animation tests: %d passed, %d failed ===" % [_passes, _failures])
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


## Waits until another dash is allowed (cooldown over and enough stamina).
func _cooldown() -> void:
	while combat.get_dash_cooldown_remaining() > 0.0 or combat.is_dashing() or not combat.has_dash_stamina():
		await physics_frame
	await _frames(1)


func _release_all() -> void:
	for action in MOVE:
		Input.action_release(action)


func _reset(at: Vector3 = OPEN_GROUND) -> void:
	_release_all()
	player.teleport_to(at)
	await _cooldown()
	await _frames(20)


func _state() -> String:
	return "state=%s speed=%.2f clip=%s one_shot=%s(%s)" % [player.movement.get_state_name(), player.get_horizontal_speed(), character.current_clip, character.is_playing_one_shot(), character.one_shot_action]


## Frames (up to limit) until the character shows clip with no one-shot; -1 if never.
func _frames_until(clip: StringName, limit: int) -> int:
	for i in limit:
		if character.current_clip == clip and not character.is_playing_one_shot():
			return i
		await physics_frame
	return -1


## Presses the dash key (a real InputEvent through CombatController._unhandled_input).
func _press_dash() -> bool:
	var dashes := [0]
	var count := func() -> void: dashes[0] += 1
	combat.dash_started.connect(count)
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = &"combat_dash"
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame
	combat.dash_started.disconnect(count)
	return dashes[0] == 1


# --- tests -------------------------------------------------------------------

func _test_clip_setup() -> void:
	print("[Clip setup]")
	_check(dash_clip != &"" and character.animation_player.get_animation(dash_clip).loop_mode != Animation.LOOP_NONE,
			"the dash falls back to a looping run clip (%s), the case that used to stick" % dash_clip)
	_check(idle_clip != run_clip and run_clip != &"" and walk_clip != &"", "idle, walk and run clips exist")


func _test_looping_one_shot_ends() -> void:
	print("[A one-shot on a looping clip ends by itself]")
	await _reset()
	character.play_once(&"dash", 1.8)
	_check(character.is_playing_one_shot() and character.current_clip == dash_clip, "one-shot playing")
	var cycle := character.animation_player.get_animation(dash_clip).length / 1.8
	var frames := await _frames_until(idle_clip, int(cycle * 60.0) + 30)
	_check(frames >= 0, "returns to idle after one cycle (%.2f s) without any end call (%d frames)" % [cycle, frames])
	character.play_once(&"dash", 1.8)
	character.end_once(&"attack")
	_check(character.is_playing_one_shot(), "end_once for another action leaves it alone")
	character.end_once(&"dash")
	_check(not character.is_playing_one_shot() and character.current_clip == idle_clip, "end_once(dash) returns to the loop at once")


func _test_run_release_idle() -> void:
	print("[Run -> release -> Idle]")
	await _reset()
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _frames(30)
	_check(player.movement.state == MovementComponent.State.RUN and character.current_clip == run_clip, "running: %s" % _state())
	_release_all()
	var frames := await _frames_until(idle_clip, 30)
	_check(frames >= 0 and player.movement.state == MovementComponent.State.IDLE, "released: idle within %d frames (%s)" % [frames, _state()])


func _test_dash_release_idle() -> void:
	print("[Dash -> release movement -> Idle]")
	await _reset()
	Input.action_press(&"move_right")
	await _frames(20)
	_check(await _press_dash(), "dash key starts a dash")
	_check(combat.is_dashing() and character.current_clip == dash_clip, "dash pose while dashing: %s" % _state())
	_release_all()
	while combat.is_dashing():
		await physics_frame
	var frames := await _frames_until(idle_clip, 30)
	_check(frames >= 0, "idle right after the dash and deceleration (%d frames): %s" % [frames, _state()])
	await _frames(90)
	_check(character.current_clip == idle_clip and player.get_horizontal_speed() < 0.01, "still idle, not running in place, 1.5 s later: %s" % _state())


func _test_dash_hold_run() -> void:
	print("[Dash -> keep holding movement -> Run]")
	await _reset()
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _frames(25)
	_check(combat.try_dash(), "dash while running")
	await physics_frame
	while combat.is_dashing():
		await physics_frame
	await _frames(1)
	_check(not character.is_playing_one_shot() and character.current_clip == run_clip and player.movement.state == MovementComponent.State.RUN,
			"run resumes the moment the dash ends: %s" % _state())
	Input.action_release(&"run")
	var frames := await _frames_until(walk_clip, 40)
	_check(frames >= 0, "letting go of run (Shift) while still moving walks: %s" % _state())
	_release_all()
	_check(await _frames_until(idle_clip, 40) >= 0, "and idles once released: %s" % _state())


func _test_repeated_dashes() -> void:
	print("[Repeated dashes recover each time]")
	await _reset()
	var blocked := [0]
	var on_block := func(ability: StringName, reason: StringName) -> void:
		if ability == &"dash" and reason in [&"cooldown", &"dashing"]:
			blocked[0] += 1
	combat.ability_blocked.connect(on_block)
	var recovered := 0
	for i in 4:
		var holding := i % 2 == 0
		if holding:
			Input.action_press(&"move_left" if i == 0 else &"move_right")
			Input.action_press(&"run")
			await _frames(15)
		_check(combat.try_dash(), "dash %d starts" % (i + 1))
		await physics_frame
		# Mashing the key during the dash and its cooldown is refused, not restarted.
		combat.try_dash()
		combat.try_dash()
		if holding:
			_release_all()
		while combat.is_dashing():
			await physics_frame
		if await _frames_until(idle_clip, 40) >= 0:
			recovered += 1
		await _cooldown()
	combat.ability_blocked.disconnect(on_block)
	_check(recovered == 4, "idle after each of 4 dashes (%d/4)" % recovered)
	_check(blocked[0] >= 8, "presses during a dash or its cooldown are refused (%d)" % blocked[0])
	# Rapid direction changes straight after a dash.
	_check(combat.try_dash(Vector3.RIGHT), "another dash")
	for action in [&"move_left", &"move_forward", &"move_right", &"move_back"]:
		Input.action_press(action)
		await _frames(2)
		Input.action_release(action)
	while combat.is_dashing():
		await physics_frame
	_check(await _frames_until(idle_clip, 40) >= 0, "rapid taps after a dash settle on idle: %s" % _state())


func _test_dash_into_wall() -> void:
	print("[Dash into an obstacle]")
	await _reset()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 3.0, 6.0)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = player.collision_mask
	level.add_child(wall)
	wall.global_position = player.global_position + Vector3(1.2, 1.5, 0)
	await _frames(2)
	var start_x := player.global_position.x
	Input.action_press(&"move_right")
	await _frames(4)
	_check(combat.try_dash(Vector3.RIGHT), "dash toward the wall")
	await physics_frame
	while combat.is_dashing():
		await physics_frame
	_check(player.global_position.x < wall.global_position.x - 0.3, "the wall stops the dash (x %.2f -> %.2f, wall %.2f)" % [start_x, player.global_position.x, wall.global_position.x])
	_check(not character.is_playing_one_shot(), "dash pose ends with the blocked dash")
	await _frames(20)
	_check(character.current_clip != dash_clip, "pushing into the wall shows no dash clip: %s" % _state())
	_release_all()
	_check(await _frames_until(idle_clip, 30) >= 0, "release against the wall: idle, no stuck run: %s" % _state())
	wall.queue_free()


func _test_bolt_during_dash() -> void:
	print("[Magic bolt during a dash]")
	await _reset()
	_check(combat.try_dash(Vector3.RIGHT), "dash")
	await physics_frame
	var bolt := combat.try_magic_bolt(Vector3.RIGHT)
	_check(bolt and character.one_shot_action == &"attack", "bolt replaces the dash pose with the attack")
	while combat.is_dashing():
		await physics_frame
	_check(character.is_playing_one_shot() and character.one_shot_action == &"attack", "the dash ending does not cut the attack short")
	_check(await _frames_until(idle_clip, 120) >= 0, "back to idle once the attack finishes: %s" % _state())


func _test_knockout_during_dash() -> void:
	print("[Knockout interrupts a dash]")
	await _reset()
	var health := combat.health
	combat.dash_invulnerable = false
	_check(combat.try_dash(Vector3.RIGHT), "dash")
	await physics_frame
	health.apply_damage(health.get_max_health() * 2.0)
	await _frames(2)
	_check(not combat.is_dashing(), "the knockout ends the dash")
	# The village's Phase 4 integration respawns a knocked-out courier at once, so the
	# death pose hands over to the get-up clip; either way the dash pose is gone.
	_check(character.one_shot_action in [&"death", &"revive"] and character.current_clip != dash_clip,
			"knockout shows death / get-up, not the dash pose: %s" % _state())
	if health.is_dead():
		health.reset()
	combat.dash_invulnerable = true
	_check(await _frames_until(idle_clip, 240) >= 0, "idle after getting up: %s" % _state())
	_check(not character.is_playing_one_shot() and character.current_clip != run_clip, "no run clip while standing still after the knockout")
