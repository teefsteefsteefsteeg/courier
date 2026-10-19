extends SceneTree
## Courier status HUD (scripts/phase4_visual/combat_hud.gd) in the real village: health
## binding with the damage chip and heal flash, shield energy against the courier's real
## maximum, rank / reputation (EXP) binding with the level badge and rank-up pulse, Bolt and
## Dash chips, a width that does not jump with longer titles, and the top-left layout
## (tracker below, nothing overlapping) at desktop and phone-aspect sizes.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/status_hud_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var combat: CombatController
var wallet: CourierWallet
var hud: Node
var gameplay_hud: GameplayHUD


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	await _frames(40)
	combat = CombatController.find_on(player)
	wallet = CourierWallet.find(self)
	hud = level.find_child("CombatHUD", true, false)
	gameplay_hud = level.get_node("GameplayHUD") as GameplayHUD
	_check(hud != null and hud.get(&"panel") is PanelContainer, "the status HUD is in the village")
	if hud == null:
		quit(_failures)
		return
	await _test_health()
	await _test_shield()
	await _test_progression()
	await _test_chips()
	await _test_layout()
	print("\n=== Status HUD tests: %d passed, %d failed ===" % [_passes, _failures])
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


## Waits until condition holds or seconds of real time pass (animations run on real time).
func _until(condition: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < end:
		await process_frame


func _test_health() -> void:
	print("[Health]")
	var bar := hud.get(&"health_bar") as ProgressBar
	var label := hud.get(&"health_label") as Label
	var trail := hud.get(&"health_trail") as ProgressBar
	_check(label.text == "HP 100 / 100" and is_equal_approx(bar.value, 100.0), "full health shown (%s)" % label.text)
	combat.health.apply_damage(40.0, player.global_position + Vector3.RIGHT)
	await _frames(2)
	_check(label.text == "HP 60 / 100" and is_equal_approx(bar.value, 60.0), "damage updates the bar and text at once")
	_check(trail.value > 90.0, "a pale damage chip stays where the health was (%.0f)" % trail.value)
	await _until(func() -> bool: return is_equal_approx(trail.value, 60.0), 3.0)
	_check(is_equal_approx(trail.value, 60.0), "the chip drains down to the new health (%.1f)" % trail.value)
	combat.health.heal(25.0)
	await _frames(2)
	var flash := hud.get(&"heal_flash") as ColorRect
	_check(label.text == "HP 85 / 100" and flash.visible and flash.size.x > 0.0, "healing raises the bar and flashes the restored segment")
	await _until(func() -> bool: return not flash.visible, 3.0)
	_check(not flash.visible, "the heal flash fades out")
	combat.health.apply_damage(70.0, player.global_position + Vector3.RIGHT)
	await _frames(2)
	_check(label.text == "HP 15 / 100", "low health shown (%s)" % label.text)
	combat.health.heal(100.0)
	await _frames(2)


func _test_shield() -> void:
	print("[Shield energy]")
	var bar := hud.get(&"shield_bar") as ProgressBar
	var label := hud.get(&"shield_label") as Label
	_check(is_equal_approx(bar.value, combat.get_shield_durability() / combat.shield_max_durability) and label.text == "Shield: Off",
			"the sapphire bar shows the courier's shield energy (%.2f, %s)" % [bar.value, label.text])
	# A raw durability equal to the maximum (60 by default) is full, not 60%.
	hud.call(&"set_shield_state", true, combat.shield_max_durability)
	_check(is_equal_approx(bar.value, 1.0) and label.text == "Shield: 100%", "raw durability is measured against the real maximum (%s)" % label.text)
	hud.call(&"set_shield_state", true, combat.shield_max_durability * 0.5)
	_check(is_equal_approx(bar.value, 0.5) and label.text == "Shield: 50%", "half the maximum reads 50%")
	hud.call(&"set_shield_state", false, 0.0)
	_check(label.text == "Shield: Broken", "an empty shield reads Broken")
	hud.call(&"set_shield_state", false, combat.shield_max_durability)


func _test_progression() -> void:
	print("[Rank and reputation]")
	var name_label := hud.get(&"name_label") as Label
	var level_label := hud.get(&"level_label") as Label
	var exp_bar := hud.get(&"exp_bar") as ProgressBar
	var exp_label := hud.get(&"exp_label") as Label
	var panel := hud.get(&"panel") as Control
	var width := panel.get_global_rect().size.x
	_check(name_label.text == "Novice Courier" and level_label.text == "1" and exp_label.text == "Rep 0 / 15", "rank 1 Novice Courier, Rep 0 / 15")
	wallet.add_reputation(9)
	await _frames(2)
	_check(exp_label.text == "Rep 9 / 15" and exp_bar.value < 0.6, "reputation text updates at once; the bar slides (%.2f)" % exp_bar.value)
	await _until(func() -> bool: return is_equal_approx(exp_bar.value, wallet.get_rank_progress()), 3.0)
	_check(is_equal_approx(exp_bar.value, wallet.get_rank_progress()), "the EXP bar reaches the rank progress (%.2f)" % exp_bar.value)
	wallet.add_reputation(8)
	await _frames(3)
	_check(level_label.text == "2" and name_label.text == "Apprentice Courier" and exp_label.text == "Rep 17 / 35", "rank-up: badge 2, Apprentice Courier, Rep 17 / 35")
	_check((hud.get(&"level_badge") as Control).scale.x > 1.01, "the level badge pulses on a rank-up")
	await _frames(5)
	_check(is_equal_approx(panel.get_global_rect().size.x, width), "the panel keeps its width with a longer title (%.0f)" % panel.get_global_rect().size.x)


func _test_chips() -> void:
	print("[Bolt and Dash chips]")
	_check((hud.get(&"bolt_label") as Label).text == "Bolt: Ready" and (hud.get(&"dash_label") as Label).text == "Dash: Ready", "both ready")
	combat.try_magic_bolt(Vector3.RIGHT)
	await _frames(2)
	_check((hud.get(&"bolt_label") as Label).text.begins_with("Bolt: 0."), "a cast shows the bolt cooldown (%s)" % (hud.get(&"bolt_label") as Label).text)
	combat.try_dash(Vector3.RIGHT)
	await _frames(2)
	var dash := (hud.get(&"dash_label") as Label).text
	_check(dash == "Dash: Dashing" or dash.begins_with("Dash: 0."), "a dash shows on the chip (%s)" % dash)


func _test_layout() -> void:
	print("[Layout]")
	var panel := hud.get(&"panel") as Control
	var minimap := gameplay_hud.get_node("Minimap")
	var journal := level.get_node("QuestJournal") as QuestJournal
	var quests := level.find_children("*", "QuestManager", true, false)
	(quests[0] as QuestManager).accept_quest(&"q001_first_delivery")
	for resolution in [Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 720), Vector2i(1950, 900)]:
		root.size = resolution
		root.content_scale_size = resolution
		await _frames(6)
		var rect := panel.get_global_rect()
		var view := Rect2(Vector2.ZERO, Vector2(resolution))
		_check(view.encloses(rect) and rect.position.x <= 20.0 and rect.position.y <= 20.0, "panel sits in the top-left corner at %s (%s)" % [resolution, rect])
		_check(gameplay_hud.quest_tracker.get_global_rect().position.y >= rect.end.y, "quest tracker starts below the panel at %s" % resolution)
		var others: Array[Control] = [gameplay_hud.quest_tracker, gameplay_hud.wallet_display, minimap.compact, journal.hint_label,
				gameplay_hud.quest_notification.panel, gameplay_hud.quick_weapon_bar, gameplay_hud.movement_guide]
		var hit: Array[String] = []
		for other in others:
			if other.is_visible_in_tree() and rect.intersects(other.get_global_rect()):
				hit.append(String(other.name))
		_check(hit.is_empty(), "panel overlaps no other HUD element at %s %s" % [resolution, hit])
		var labels: Array[Label] = [hud.get(&"name_label"), hud.get(&"health_label"), hud.get(&"shield_label"), hud.get(&"exp_label"), hud.get(&"bolt_label"), hud.get(&"dash_label")]
		var spill: Array[String] = []
		for label in labels:
			if not rect.encloses(label.get_global_rect()):
				spill.append(String(label.name))
		_check(spill.is_empty(), "every label stays inside the panel at %s %s" % [resolution, spill])
		_check(panel.scale.x >= 0.72 and panel.scale.x <= 1.0, "panel scale %.2f at %s" % [panel.scale.x, resolution])
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
