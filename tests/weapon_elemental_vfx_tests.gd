extends SceneTree
## Phase 8 weapon elemental rework, in the real village:
## - Passive: every weapon class (sword, axe, bow, staff) at +1..+5 has its own elements
##   (no element shared between classes at a level, no two levels of a class alike),
##   animated (flipbooks, particles, spinners), within budget; +0 shows nothing; passive
##   effects deal no damage; the bow's stay below its top limb and draw over the body;
##   effects survive a teleport and a region change.
## - Active: normal attacks spawn their weapon's own effects (sword ember burst / fire arc,
##   axe ground ring, bow wind spiral / charged arrow, staff droplet trail); damage stays the
##   weapon's own; a normal attack never fires an ultimate.
## - Ultimates (+5, [C]): Flame Slash hits what is ahead in its band, once each, not behind
##   or beside; Earthquake hits and staggers inside its radius only; Thunder Arrow chains to
##   up to 3 nearby enemies, each once; Arcane Storm strikes repeatedly; cooldowns; below +5
##   refused; an MP source that refuses blocks the storm; the HUD line; works in Wyrmfall.
##   godot --headless --path . --script res://tests/weapon_elemental_vfx_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const SLIME := "res://scenes/gameplay/combat/forest_slime.tscn"
const ARENA := Vector3(5.6, 0, -11.0)
## Skills are aimed south from ARENA, over the open plaza (the Armory stands to the north).
const AIM := Vector3.BACK
const WEAPONS := {&"steel_sword": "sword", &"battle_axe": "axe", &"hunting_bow": "bow", &"magic_staff": "staff"}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var visuals: EnhancementVisuals
var effects: AttackEffects
var ultimates: WeaponUltimates
var combat: CombatController
var router: Node
var dummies: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://weapon_elemental_vfx_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	visuals = EnhancementVisuals.find(self)
	effects = AttackEffects.find(self)
	ultimates = WeaponUltimates.find(self)
	combat = CombatController.find_on(player)
	router = get_first_node_in_group(&"phase6_router")
	await _frames(20)
	for id in WEAPONS:
		inventory.add_item(inventory.get_definition(id))

	await _test_passive()
	await _test_passive_harmless_and_moves()
	await _test_active()
	await _test_flame_slash()
	await _test_earthquake()
	await _test_thunder_arrow()
	await _test_arcane_storm()
	await _test_rules_and_hud()
	await _test_after_region_change()

	print("\n=== Weapon elemental VFX tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _equip(id: StringName, lvl: int) -> void:
	inventory.equip(id)
	inventory.set_enhancement(id, lvl)
	await _frames(4)


## A frozen forest slime (training dummy) at offset from the courier, facing nowhere.
func _dummy(at: Vector3, health := 2000.0) -> Enemy:
	var slime := (load(SLIME) as PackedScene).instantiate() as Enemy
	slime.simulate = false
	(player.get_parent() as Node).add_child(slime)
	slime.global_position = at
	slime.health.max_health = health
	slime.health.reset()
	dummies.append(slime)
	return slime


func _clear_dummies() -> void:
	for dummy: Variant in dummies:
		if is_instance_valid(dummy):
			(dummy as Node).queue_free()
	dummies.clear()
	await _physics(3)


## A point d metres ahead along AIM and r to its right.
func _at(d: float, r: float = 0.0) -> Vector3:
	return ARENA + AIM * d + AIM.cross(Vector3.UP) * r


## The courier at ARENA facing direction (an aim along it).
func _face(direction: Vector3) -> void:
	player.teleport_to(ARENA)
	await _physics(5)
	var visual := player.facing.visual_root if player.facing != null else null
	if visual != null:
		visual.rotation.y = FacingComponent.yaw_for_direction(direction)
	await _physics(2)


func _hits_by(log: Array, skill: StringName) -> Dictionary:
	var counts := {}
	for entry: Array in log:
		if entry[0] == skill:
			counts[entry[1]] = int(counts.get(entry[1], 0)) + 1
	return counts


# --- passive -----------------------------------------------------------------

func _test_passive() -> void:
	print("[Passive: one identity per weapon and level]")
	var sets := {}
	for id in WEAPONS:
		var label: String = WEAPONS[id]
		await _equip(id, 0)
		_check(visuals.weapon_glow == null, "%s +0: no effect" % label)
		for lvl in range(1, 6):
			await _equip(id, lvl)
			var glow := visuals.weapon_glow
			if glow == null:
				_check(false, "%s +%d: an effect" % [label, lvl])
				continue
			var own := glow.elements.filter(func(e: StringName) -> bool: return e != &"light")
			var prefixed := own.all(func(e: StringName) -> bool: return String(e).begins_with(label + "_"))
			_check(not own.is_empty() and prefixed, "%s +%d %s: its own elements %s" % [label, lvl, EnhancementGlow.tier_name(glow.weapon_type, lvl), own])
			var particle_count := 0
			for p in glow.particles:
				particle_count += p.amount
			_check(glow.strips.size() + glow.particles.size() + glow.shapes.size() > 0 and glow.strips.size() <= 6 and particle_count <= 60,
					"%s +%d: animated, within budget (%d flipbooks, %d particles, %d shapes)" % [label, lvl, glow.strips.size(), particle_count, glow.shapes.size()])
			sets["%s%d" % [label, lvl]] = own
	for lvl in range(1, 6):
		var shared: Array[String] = []
		var labels: Array = WEAPONS.values()
		for i in labels.size():
			for j in range(i + 1, labels.size()):
				for e: StringName in sets.get("%s%d" % [labels[i], lvl], []):
					if (sets.get("%s%d" % [labels[j], lvl], []) as Array).has(e):
						shared.append("%s/%s:%s" % [labels[i], labels[j], e])
		_check(shared.is_empty(), "+%d: no element shared between weapon classes %s" % [lvl, shared])
	for label: String in WEAPONS.values():
		var alike: Array[String] = []
		for a in range(1, 6):
			for b in range(a + 1, 6):
				var sa: Array = (sets.get("%s%d" % [label, a], []) as Array).duplicate()
				var sb: Array = (sets.get("%s%d" % [label, b], []) as Array).duplicate()
				sa.sort()
				sb.sort()
				if sa == sb:
					alike.append("+%d=+%d" % [a, b])
		_check(alike.is_empty(), "%s: every level is a different composition %s" % [label, alike])
	# The bow: over the body, nothing above its top limb.
	await _equip(&"hunting_bow", 5)
	var bow := visuals.weapon_glow
	var highest := -INF
	for strip in bow.strips:
		highest = maxf(highest, _span_fraction(bow, strip.position))
	_check(bow.shows_over_body and highest <= EnhancementGlow.BOW_TOP + 0.05, "bow +5: over the body, effects at or below its top limb (%.2f)" % highest)


## Where a point sits on a bow's span (0 = lower limb, 1 = upper limb).
func _span_fraction(glow: EnhancementGlow, point: Vector3) -> float:
	var a := glow._bow_at(0.0)
	var b := glow._bow_at(1.0)
	return (point - a).dot(b - a) / maxf((b - a).length_squared(), 0.000001)


func _test_passive_harmless_and_moves() -> void:
	print("[Passive: harmless, follows the courier]")
	await _equip(&"steel_sword", 5)
	await _face(Vector3.FORWARD)
	var slime := _dummy(ARENA + Vector3(0.9, 0, 0))
	var before := slime.health.get_health()
	await _seconds(1.5)
	_check(is_equal_approx(slime.health.get_health(), before), "a +5 inferno blade next to an enemy deals no damage")
	await _clear_dummies()
	var glow := visuals.weapon_glow
	player.teleport_to(ARENA + Vector3(-10, 0, 6))
	await _physics(10)
	_check(visuals.weapon_glow == glow and is_instance_valid(glow) and glow.is_inside_tree(), "the effect stays on the blade after a teleport")
	player.teleport_to(ARENA)
	await _physics(5)


# --- active ------------------------------------------------------------------

func _attack_kinds(direction: Vector3) -> Array[StringName]:
	var kinds: Array[StringName] = []
	var collect := func(kind: StringName, _effect: Node3D) -> void: kinds.append(kind)
	effects.effect_spawned.connect(collect)
	combat.try_attack(direction)
	await _seconds(0.7)
	effects.effect_spawned.disconnect(collect)
	return kinds


func _test_active() -> void:
	print("[Active: normal attacks]")
	await _face(Vector3.FORWARD)
	var cases := [
		[&"steel_sword", 3, &"sword_ember_burst"], [&"steel_sword", 5, &"sword_heat_flash"],
		[&"battle_axe", 4, &"axe_ground_ring"], [&"battle_axe", 5, &"axe_quake_blast"],
		[&"hunting_bow", 3, &"bow_wind_spiral"], [&"hunting_bow", 5, &"bow_charged_arrow"],
		[&"magic_staff", 3, &"staff_droplet_trail"], [&"magic_staff", 5, &"staff_crystal_stream"],
	]
	for case in cases:
		await _equip(case[0], case[1])
		await _seconds(0.7)
		var kinds := await _attack_kinds(Vector3.FORWARD)
		_check(kinds.has(case[2]), "%s +%d attack: %s (%s)" % [WEAPONS[case[0]], case[1], case[2], kinds])
	# Damage is the weapon's own and no ultimate fires from Space.
	await _equip(&"steel_sword", 5)
	await _seconds(0.7)
	var slime := _dummy(ARENA + Vector3(0, 0, -1.2))
	var before := slime.health.get_health()
	ultimates.cooldowns.clear()
	combat.try_attack(Vector3.FORWARD)
	await _seconds(0.7)
	_check(is_equal_approx(before - slime.health.get_health(), combat.melee_damage), "a +5 sword's normal hit deals its own damage (%.1f of %.1f)" % [before - slime.health.get_health(), combat.melee_damage])
	_check(ultimates.cooldowns.is_empty(), "a normal attack does not fire the ultimate")
	await _clear_dummies()


# --- ultimates ---------------------------------------------------------------

func _test_flame_slash() -> void:
	print("[Sword +5: Flame Slash]")
	await _equip(&"steel_sword", 4)
	await _face(AIM)
	_check(not ultimates.use(), "a +4 sword has no ultimate")
	await _equip(&"steel_sword", 5)
	await _face(AIM)
	var ahead := _dummy(_at(5))
	var far := _dummy(_at(9))
	var behind := _dummy(_at(-3))
	var beside := _dummy(_at(5, 4.5))
	var log: Array = []
	var record := func(skill: StringName, target: Node, amount: float) -> void: log.append([skill, target, amount])
	ultimates.skill_hit.connect(record)
	var spawned: Array[StringName] = []
	var watch := func(kind: StringName, _e: Node3D) -> void: spawned.append(kind)
	ultimates.effect_spawned.connect(watch)
	_check(ultimates.use(), "C with a +5 sword releases the Flame Slash")
	await _seconds(1.3)
	var hits := _hits_by(log, &"flame_slash")
	_check(hits.get(ahead, 0) == 1 and hits.get(far, 0) == 1, "the wave burns both enemies ahead, once each (%s)" % [hits.values()])
	_check(not hits.has(behind) and not hits.has(beside), "nothing behind or beside the wave")
	var expected := combat.melee_damage * float(WeaponUltimates.SKILLS[ItemDefinition.WeaponType.SWORD]["factor"])
	_check(log.size() > 0 and is_equal_approx(float(log[0][2]), expected), "fire damage is %.0f (2.2x the blade)" % expected)
	_check(spawned.has(&"flame_slash"), "the wave is a real effect in the world")
	_check(not ultimates.use(), "on cooldown right after (%.1f s)" % ultimates.get_cooldown_remaining())
	ultimates.skill_hit.disconnect(record)
	ultimates.effect_spawned.disconnect(watch)
	ultimates.cooldowns.clear()
	await _clear_dummies()


func _test_earthquake() -> void:
	print("[Axe +5: Earthquake]")
	await _equip(&"battle_axe", 5)
	await _face(AIM)
	var near := _dummy(_at(3))
	var ring := _dummy(_at(3, 4.5))
	var outside := _dummy(_at(11))
	var log: Array = []
	var record := func(skill: StringName, target: Node, amount: float) -> void: log.append([skill, target, amount])
	ultimates.skill_hit.connect(record)
	_check(ultimates.use(), "C with a +5 axe releases the Earthquake")
	await _seconds(1.1)
	var hits := _hits_by(log, &"earthquake")
	_check(hits.get(near, 0) == 1 and hits.get(ring, 0) == 1, "the shockwave hits both enemies inside it, once each")
	_check(not hits.has(outside), "not the one beyond its radius")
	_check(near.is_staggered() and ring.is_staggered() and not outside.is_staggered(), "the enemies it hit are staggered")
	ultimates.skill_hit.disconnect(record)
	ultimates.cooldowns.clear()
	await _clear_dummies()


func _test_thunder_arrow() -> void:
	print("[Bow +5: Thunder Arrow]")
	await _equip(&"hunting_bow", 5)
	await _face(AIM)
	var first := _dummy(_at(6))
	var second := _dummy(_at(7, 3))
	var third := _dummy(_at(8, -3))
	var fourth := _dummy(_at(11, 2))
	var fifth := _dummy(_at(12, -2))
	var far := _dummy(_at(6, 14))
	var log: Array = []
	var record := func(skill: StringName, target: Node, amount: float) -> void: log.append([skill, target, amount])
	ultimates.skill_hit.connect(record)
	var strikes: Array[StringName] = []
	var watch := func(kind: StringName, _e: Node3D) -> void: strikes.append(kind)
	ultimates.effect_spawned.connect(watch)
	_check(ultimates.use(), "C with a +5 bow looses the Thunder Arrow")
	await _seconds(1.6)
	var primary := _hits_by(log, &"thunder_arrow")
	var chain := _hits_by(log, &"thunder_arrow_chain")
	_check(primary.size() == 1 and primary.get(first, 0) == 1, "the arrow strikes the first enemy in its path")
	_check(chain.size() == 3 and chain.values().all(func(n: int) -> bool: return n == 1), "lightning chains to 3 others, each once (%d)" % chain.size())
	_check(not chain.has(first) and not chain.has(far) and not primary.has(far), "never back to the first one, never the distant one")
	_check(strikes.count(&"lightning_strike") >= 4, "a lightning strike on every target (%d)" % strikes.count(&"lightning_strike"))
	ultimates.skill_hit.disconnect(record)
	ultimates.effect_spawned.disconnect(watch)
	ultimates.cooldowns.clear()
	await _clear_dummies()


func _test_arcane_storm() -> void:
	print("[Staff +5: Arcane Storm]")
	await _equip(&"magic_staff", 5)
	await _face(AIM)
	var one := _dummy(_at(6))
	var two := _dummy(_at(6.5, 1.0))
	var outside := _dummy(_at(16))
	var log: Array = []
	var record := func(skill: StringName, target: Node, amount: float) -> void: log.append([skill, target, amount])
	ultimates.skill_hit.connect(record)
	var bolts: Array[StringName] = []
	var watch := func(kind: StringName, _e: Node3D) -> void:
		if kind == &"storm_bolt":
			bolts.append(kind)
	ultimates.effect_spawned.connect(watch)
	_check(ultimates.use(), "C with a +5 staff calls the Arcane Storm (no MP system yet: cooldown only)")
	await _seconds(3.2)
	var hits := _hits_by(log, &"arcane_storm")
	var strikes := int(WeaponUltimates.SKILLS[ItemDefinition.WeaponType.STAFF]["strikes"])
	_check(bolts.size() == strikes, "%d timed arcane bolts fall (%d)" % [strikes, bolts.size()])
	_check(hits.get(one, 0) >= 2 and hits.get(two, 0) >= 2, "both enemies in the circle are struck several times (%s)" % [hits.values()])
	_check(hits.get(one, 0) <= strikes and hits.get(two, 0) <= strikes and not hits.has(outside), "at most once per strike, nothing outside the circle")
	ultimates.skill_hit.disconnect(record)
	ultimates.effect_spawned.disconnect(watch)
	ultimates.cooldowns.clear()
	# An MP source that refuses blocks it.
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc spend(_amount: float) -> bool:\n\treturn false\n"
	script.reload()
	var mana := Node.new()
	mana.set_script(script)
	mana.add_to_group(WeaponUltimates.MANA_GROUP)
	root.add_child(mana)
	var reasons: Array[StringName] = []
	var blocked := func(_skill: StringName, reason: StringName) -> void: reasons.append(reason)
	ultimates.ultimate_blocked.connect(blocked)
	_check(not ultimates.use() and reasons.has(&"mana"), "without enough MP the storm is refused")
	ultimates.ultimate_blocked.disconnect(blocked)
	mana.queue_free()
	await _clear_dummies()


func _test_rules_and_hud() -> void:
	print("[The C key and the HUD]")
	var bar := level.find_child("QuickWeaponBar", true, false) as QuickWeaponBar
	await _equip(&"steel_sword", 4)
	await _frames(3)
	_check(bar != null and not bar.ultimate_label.visible, "+4: no ultimate line on the weapon bar")
	await _equip(&"steel_sword", 5)
	await _frames(3)
	_check(bar.ultimate_label.visible and bar.ultimate_label.text == "[C] Flame Slash  ·  ready", "+5: %s" % bar.ultimate_label.text)
	await _face(AIM)
	var used: Array[StringName] = []
	var on_used := func(skill: StringName) -> void: used.append(skill)
	ultimates.ultimate_used.connect(on_used)
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_C
		event.physical_keycode = KEY_C
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame
		await process_frame
	ultimates.ultimate_used.disconnect(on_used)
	_check(used == [&"flame_slash"], "the real C key releases it (%s)" % [used])
	await _frames(3)
	_check(bar.ultimate_label.text.ends_with(" s"), "the line counts the cooldown (%s)" % bar.ultimate_label.text)
	await _seconds(1.2)
	ultimates.cooldowns.clear()
	await _equip(&"woodcutter_axe" if inventory.get_definition(&"woodcutter_axe") != null else &"steel_sword", 0)


func _test_after_region_change() -> void:
	print("[After a region change]")
	await _equip(&"battle_axe", 5)
	router.call(&"travel", &"wyrmfall", &"Arrival", player)
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == &"wyrmfall" and not router.get(&"crossing"):
			break
	await _physics(10)
	_check(visuals.weapon_glow != null and visuals.weapon_glow.is_inside_tree() and visuals.weapon_glow.weapon_type == ItemDefinition.WeaponType.AXE, "the axe's effect is still on it in Wyrmfall")
	var visual := player.facing.visual_root if player.facing != null else null
	if visual != null:
		visual.rotation.y = FacingComponent.yaw_for_direction(Vector3.FORWARD)
	await _physics(2)
	var slime := _dummy(player.global_position + Vector3(0, 0.2, -3))
	var log: Array = []
	var record := func(skill: StringName, target: Node, amount: float) -> void: log.append([skill, target, amount])
	ultimates.skill_hit.connect(record)
	_check(ultimates.use(), "the Earthquake works in Wyrmfall")
	await _seconds(1.0)
	_check(_hits_by(log, &"earthquake").get(slime, 0) == 1, "and hits an enemy there")
	ultimates.skill_hit.disconnect(record)
	ultimates.cooldowns.clear()
	await _clear_dummies()
	router.call(&"travel", &"village", &"", player)
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == &"village" and not router.get(&"crossing"):
			break
