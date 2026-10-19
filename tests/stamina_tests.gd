extends SceneTree
## Dash stamina on the courier's CombatController, and the status HUD's Dash chip, in the
## real village. Regression for "dash consumes stamina but it never regenerates": the
## combat visual adapter fed the HUD's own "dashing" flag back to it every frame, so after
## the first dash the chip stayed "Dash: Dashing" with an empty bar forever. Timers are
## driven with exact deltas (simulate off) so the regeneration delay is checked precisely.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/stamina_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const STEP := 1.0 / 60.0

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var combat: CombatController
var hud: Node
var character: KayKitCharacter


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	await _frames(20)
	combat = CombatController.find_on(player)
	hud = level.find_child("CombatHUD", true, false)
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	combat.simulate = false
	await _test_consume_and_regenerate()
	await _test_repeated_dashes_reset_delay()
	await _test_zero_blocks_then_recovers()
	await _test_hud_and_animation()
	print("\n=== Stamina tests: %d passed, %d failed ===" % [_passes, _failures])
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


## Advances the controller by seconds in exact physics steps.
func _advance(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		combat.advance(STEP)


func _dash() -> bool:
	var ok := combat.try_dash(Vector3.RIGHT)
	_advance(combat.dash_duration + STEP)
	return ok


func _test_consume_and_regenerate() -> void:
	print("[Consume and regenerate]")
	_check(is_equal_approx(combat.get_stamina(), combat.max_stamina), "starts full (%.0f)" % combat.get_stamina())
	_check(combat.stamina_regen_delay >= 0.6 and combat.stamina_regen_delay <= 1.0, "regeneration delay %.2f s" % combat.stamina_regen_delay)
	_check(_dash(), "dash")
	var after := combat.get_stamina()
	_check(is_equal_approx(after, combat.max_stamina - combat.dash_stamina_cost), "the dash spent %.0f stamina (%.0f left)" % [combat.dash_stamina_cost, after])
	_advance(combat.stamina_regen_delay - 0.1)
	_check(is_equal_approx(combat.get_stamina(), after), "no regeneration during the delay")
	_advance(0.2)
	_check(combat.get_stamina() > after, "regeneration starts after the delay (%.1f)" % combat.get_stamina())
	var before := combat.get_stamina()
	_advance(0.1)
	_check(is_equal_approx(combat.get_stamina() - before, combat.stamina_regen_per_second * 0.1), "regeneration is per second (delta-based)")
	_advance(3.0)
	_check(is_equal_approx(combat.get_stamina(), combat.max_stamina), "back to full after waiting, never above the maximum")


func _test_repeated_dashes_reset_delay() -> void:
	print("[Repeated dashes]")
	_dash()
	_advance(combat.dash_cooldown)
	_advance(0.0)
	var low := combat.get_stamina()
	_check(_dash(), "second dash once the cooldown allows it")
	var after_second := combat.get_stamina()
	_check(after_second < low, "it spent stamina again")
	_advance(combat.stamina_regen_delay - 0.1)
	_check(is_equal_approx(combat.get_stamina(), after_second), "the new dash restarted the delay")
	_advance(4.0)
	_check(is_equal_approx(combat.get_stamina(), combat.max_stamina), "repeated dashes never block regeneration for good")


func _test_zero_blocks_then_recovers() -> void:
	print("[Empty stamina]")
	var blocked := []
	combat.ability_blocked.connect(func(ability: StringName, reason: StringName) -> void: blocked.append([ability, reason]))
	var dashes := 0
	while combat.has_dash_stamina() and dashes < 20:
		_dash()
		dashes += 1
		_advance(combat.dash_cooldown)
	_check(not combat.has_dash_stamina() and combat.get_stamina() >= 0.0, "stamina ran low after %d quick dashes (%.1f, never below zero)" % [dashes, combat.get_stamina()])
	_check(not combat.try_dash(Vector3.RIGHT) and blocked.back() == [&"dash", &"no_stamina"], "a dash without stamina is refused (no_stamina)")
	_advance(combat.stamina_regen_delay + 1.0)
	_check(combat.has_dash_stamina() and combat.try_dash(Vector3.LEFT), "stamina regenerates from empty and the dash works again")
	_advance(5.0)


func _test_hud_and_animation() -> void:
	print("[HUD and animation]")
	combat.simulate = true
	await _frames(5)
	var label := hud.get(&"dash_label") as Label
	var bar := hud.get(&"dash_bar") as ProgressBar
	_check(label.text == "Dash: Ready" and is_equal_approx(bar.value, 1.0), "chip ready and full (%s, %.2f)" % [label.text, bar.value])
	combat.try_dash(Vector3.RIGHT)
	await _frames(2)
	_check(label.text == "Dash: Dashing" or label.text.begins_with("Dash: 0."), "a dash shows on the chip (%s)" % label.text)
	_check(bar.value < 0.8, "the chip's bar shows the spent stamina (%.2f)" % bar.value)
	await _until(func() -> bool: return is_equal_approx(bar.value, 1.0), 4.0)
	_check(label.text == "Dash: Ready" and is_equal_approx(bar.value, 1.0), "the chip returns to Ready and full after waiting (regression: stuck on Dashing) (%s, %.2f)" % [label.text, bar.value])
	_check(character.one_shot_action != &"dash", "the dash pose ended")
	combat.simulate = false
	while combat.has_dash_stamina():
		combat.try_dash(Vector3.RIGHT)
		_advance(combat.dash_duration + combat.dash_cooldown + STEP)
	await _frames(3)
	_check(label.text == "Dash: Tired", "the chip says Tired while a dash cannot be afforded (%s)" % label.text)
	combat.simulate = true
	await _until(func() -> bool: return label.text == "Dash: Ready", 4.0)
	_check(label.text == "Dash: Ready", "and Ready again once stamina is back")


## Waits until condition holds or seconds of real time pass.
func _until(condition: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < end:
		await process_frame
