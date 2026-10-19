extends SceneTree
## Phase 8 milestone 3: weapon enhancement VFX rework, in the real village.
## - Each level +1..+5 is a different set of animated elements (sparks / nature / water /
##   lightning / legendary fire + lightning + water); +0 has none.
## - Placement follows the weapon: blade (sword), head (axe), both limbs (bow), top (staff).
## - Swings and hits add tier effects: water trail and splash (+3), lightning flash and
##   electric impact (+4), a legendary fire arc, blast and strike (+5); +0..+2 keep the
##   plain arc and flash. Damage and swing timing are unchanged by the effects.
## - Budgets: at most 6 flipbooks and 40 particles per weapon; particles trail in world space.
##   godot --headless --path . --script res://tests/phase8_weapon_vfx_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const ARENA := Vector3(5.6, 0, -11.0)

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var combat: CombatController
var character: KayKitCharacter
var visuals: EnhancementVisuals
var attack_fx: AttackEffects
var target: StaticBody3D
var target_health: CombatHealth


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	UISettings.persist = false
	UISettings.set_value(UISettings.SHOW_ENHANCEMENT_VFX, true)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_weapon_vfx_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	combat = CombatController.find_on(player)
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	visuals = EnhancementVisuals.find(self)
	attack_fx = AttackEffects.find(self)
	await _frames(20)
	for id in [&"iron_sword", &"battle_axe", &"hunting_bow", &"magic_staff"]:
		inventory.add_item(inventory.get_definition(id))
	player.teleport_to(ARENA)
	await _physics(10)

	await _test_tiers()
	await _test_placement()
	await _test_attack_tiers()

	UISettings.reload()
	print("\n=== Phase 8 weapon VFX tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _glow_for(item_id: StringName, lvl: int) -> EnhancementGlow:
	inventory.equip(item_id)
	inventory.set_enhancement(item_id, lvl)
	await _frames(4)
	return visuals.weapon_glow


func _test_tiers() -> void:
	print("[Tiers]")
	var expected := {
		1: [&"spark", &"glint", &"motes"],
		2: [&"nature", &"leaves"],
		3: [&"swirl", &"bubbles", &"drips"],
		4: [&"crackle", &"bolt", &"light"],
		5: [&"flame", &"crackle", &"swirl", &"embers", &"light"],
	}
	var glow0 := await _glow_for(&"iron_sword", 0)
	_check(glow0 == null, "+0 NORMAL: no enhancement effect")
	for lvl in expected:
		var glow := await _glow_for(&"iron_sword", lvl)
		if glow == null:
			_check(false, "+%d has an effect" % lvl)
			continue
		var missing: Array = (expected[lvl] as Array).filter(func(e: StringName) -> bool: return not glow.elements.has(e))
		_check(missing.is_empty(), "+%d %s has %s (missing %s, has %s)" % [lvl, EnhancementGlow.TIER_NAMES[lvl], expected[lvl], missing, glow.elements])
		var amount := 0
		for p in glow.particles:
			amount += p.amount
			_check(not p.local_coords, "+%d %s particles trail in world space" % [lvl, p.name])
		_check(glow.strips.size() <= 6 and amount <= 40, "+%d stays light: %d flipbooks, %d particles" % [lvl, glow.strips.size(), amount])
	# Lower tiers never borrow the elements of higher ones.
	var g1 := await _glow_for(&"iron_sword", 1)
	_check(not g1.elements.has(&"flame") and not g1.elements.has(&"crackle") and not g1.elements.has(&"swirl"), "+1 has no fire, lightning or water")
	var g3 := await _glow_for(&"iron_sword", 3)
	_check(not g3.elements.has(&"flame") and not g3.elements.has(&"crackle"), "+3 is water only (no fire, no lightning)")
	var g4 := await _glow_for(&"iron_sword", 4)
	_check(not g4.elements.has(&"flame") and not g4.elements.has(&"swirl"), "+4 is lightning only (no fire, no water)")
	# Every flipbook animates.
	var g5 := await _glow_for(&"iron_sword", 5)
	var frames_before: Array[int] = []
	for strip in g5.strips:
		frames_before.append(strip.frame)
	await create_timer(0.4).timeout
	var moved := 0
	for i in g5.strips.size():
		if g5.strips[i].frame != frames_before[i] or not g5.strips[i].loop:
			moved += 1
	_check(moved == g5.strips.size(), "+5: every flipbook animates (%d/%d)" % [moved, g5.strips.size()])


## t (0 = grip, 1 = tip) of an effect point along the glow's grip-to-tip axis.
func _t_of(glow: EnhancementGlow, point: Vector3) -> float:
	var axis := glow.tip - Vector3.ZERO
	return point.dot(axis) / axis.length_squared()


func _test_placement() -> void:
	print("[Placement per weapon]")
	for case in [[&"iron_sword", 0.25, 1.05, "along the blade"], [&"battle_axe", 0.55, 1.05, "round the axe head"], [&"magic_staff", 0.65, 1.05, "at the top of the staff"]]:
		var glow := await _glow_for(case[0], 3)
		var ts: Array[float] = []
		for strip in glow.strips:
			ts.append(_t_of(glow, strip.position))
		_check(not ts.is_empty() and ts.min() >= case[1] and ts.max() <= case[2], "%s: effects %s (t %.2f..%.2f)" % [case[0], case[3], ts.min() if not ts.is_empty() else -1.0, ts.max() if not ts.is_empty() else -1.0])
	var bow := await _glow_for(&"hunting_bow", 1)
	var low := INF
	var high := -INF
	for strip in bow.strips:
		var t := _t_of(bow, strip.position)
		low = minf(low, t)
		high = maxf(high, t)
	for p in bow.particles:
		for point in p.emission_points:
			var t := _t_of(bow, point)
			low = minf(low, t)
			high = maxf(high, t)
	_check(low < -0.3 and high > 0.3, "hunting bow: effects on both limbs (t %.2f..%.2f)" % [low, high])
	# Regression: the bow is held across the body, so its effects were hidden behind the
	# courier from the gameplay camera; they now draw over the body.
	for level in [1, 4, 5]:
		var bow_glow := await _glow_for(&"hunting_bow", level)
		var over := bow_glow.shows_over_body and not bow_glow.strips.is_empty()
		for strip in bow_glow.strips:
			over = over and (strip.material_override as StandardMaterial3D).no_depth_test
		for p in bow_glow.particles:
			over = over and ((p.mesh as QuadMesh).material as StandardMaterial3D).no_depth_test
		_check(over, "hunting bow +%d: every effect draws over the courier's body" % level)
	var sword_glow := await _glow_for(&"iron_sword", 4)
	_check(not sword_glow.shows_over_body and not (sword_glow.strips[0].material_override as StandardMaterial3D).no_depth_test, "a sword's effects keep normal depth")
	# Still attached while the courier runs.
	var glow := await _glow_for(&"iron_sword", 5)
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _physics(30)
	Input.action_release(&"move_right")
	Input.action_release(&"run")
	_check(visuals.weapon_glow == glow and glow.get_parent() == character.get_held_item_node() and player.get_horizontal_speed() > 0.1, "the effect stays on the weapon while running")
	player.teleport_to(ARENA)
	await _physics(10)


func _spawn_target(offset: Vector3) -> void:
	if target != null and is_instance_valid(target):
		target.queue_free()
	target = StaticBody3D.new()
	target.collision_layer = CombatController.ENEMY_LAYER
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	shape.shape = capsule
	shape.position = Vector3(0, 0.9, 0)
	target.add_child(shape)
	target_health = CombatHealth.new()
	target_health.max_health = 100000.0
	target.add_child(target_health)
	level.add_child(target)
	target.global_position = player.global_position + offset
	await _physics(3)


func _test_attack_tiers() -> void:
	print("[Attack trails and impacts by tier]")
	var aim := Vector3.BACK
	var expected := {
		0: [], 1: [], 2: [],
		3: [&"water_trail", &"water_splash"],
		4: [&"lightning_flash", &"electric_impact"],
		5: [&"legendary_trail", &"lightning_flash", &"legendary_blast", &"electric_impact"],
	}
	var sword := inventory.get_definition(&"iron_sword")
	await _spawn_target(aim * 1.2)
	for lvl in expected:
		inventory.equip(&"iron_sword")
		inventory.set_enhancement(&"iron_sword", lvl)
		await _frames(3)
		for i in 240:
			if combat.is_magic_bolt_ready() and not combat.is_melee_pending():
				break
			await physics_frame
		var kinds: Array[StringName] = []
		var on_spawn := func(kind: StringName, _effect: Node3D) -> void: kinds.append(kind)
		attack_fx.effect_spawned.connect(on_spawn)
		var before := target_health.get_health()
		var strike_in := -1.0
		if combat.try_attack(aim):
			strike_in = character.get_strike_remaining()
		await _physics(24)
		attack_fx.effect_spawned.disconnect(on_spawn)
		var dealt := before - target_health.get_health()
		var missing: Array = (expected[lvl] as Array).filter(func(k: StringName) -> bool: return not kinds.has(k))
		var extra: Array = kinds.filter(func(k: StringName) -> bool: return k not in [&"swing", &"impact"] and not (expected[lvl] as Array).has(k))
		_check(kinds.has(&"swing") and kinds.has(&"impact") and missing.is_empty() and extra.is_empty(), "+%d: %s (got %s)" % [lvl, expected[lvl] if not (expected[lvl] as Array).is_empty() else "plain arc and flash", kinds])
		_check(is_equal_approx(dealt, sword.attack_damage * Enhancement.damage_multiplier(lvl)), "+%d: the hit still deals %.0f" % [lvl, dealt])
		_check(absf(strike_in - combat.melee_windup) < 0.02, "+%d: swing timing unchanged (strike in %.3f s)" % [lvl, strike_in])
	await create_timer(1.8).timeout
	var leftovers := level.find_children("Fx_*", "", true, false).size() + level.find_children("ImpactFlash", "", true, false).size()
	_check(leftovers == 0, "every one-shot effect removed itself (%d left)" % leftovers)
