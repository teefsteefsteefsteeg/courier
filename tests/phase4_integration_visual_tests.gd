extends SceneTree
## Phase 4 integration visual checks (live encounter presentation layer: enemy
## visuals + health bars, hit / death feedback, combat VFX reuse, package
## warnings, forest route + quest indicators, standalone preview).
##   godot --headless --path . --script res://tests/phase4_integration_visual_tests.gd
## Exit code = number of failed checks. Independent of gameplay combat code:
## gameplay nodes are mocked with runtime GDScript exposing the contract names.

const Assets := preload("res://scripts/phase4_integration_visual/integration_assets.gd")
const HealthBar := preload("res://scripts/phase4_integration_visual/enemy_health_bar.gd")
const DefeatBurst := preload("res://scripts/phase4_integration_visual/defeat_burst_vfx.gd")
const EnemyVisual := preload("res://scripts/phase4_visual/enemy_visual.gd")
const SlimeScript := preload("res://scripts/phase4_visual/forest_slime_visual.gd")
const WispScript := preload("res://scripts/phase4_visual/frost_wisp_visual.gd")
const MagicBolt := preload("res://scripts/phase4_visual/magic_bolt_vfx.gd")
const DashVfx := preload("res://scripts/phase4_visual/dash_vfx.gd")
const DamageNumber := preload("res://scripts/phase4_visual/damage_number_vfx.gd")
const PRESENTATION_SCENE := "res://scenes/gameplay/phase4_integration_visual/encounter_presentation.tscn"
const PREVIEW_SCENE := "res://scenes/gameplay/phase4_integration_visual/encounter_preview.tscn"
const SLIME_SCENE := "res://scenes/phase4_visual/enemies/forest_slime.tscn"
const S := EnemyVisual.State

const CONTROLLER_SRC := "extends Node\n" \
	+ "signal magic_bolt_fired(origin, direction)\n" \
	+ "signal dash_started\n" \
	+ "signal dash_finished\n" \
	+ "signal shield_changed(active, durability)\n" \
	+ "signal target_hit(target, amount)\n"
const HEALTH_SRC := "extends Node\n" \
	+ "signal health_changed(current, maximum)\n" \
	+ "signal damaged(amount, source_position)\n" \
	+ "signal died\n" \
	+ "var current_health := 30.0\n" \
	+ "var max_health := 30.0\n"
const PACKAGE_SRC := "extends Node\n" \
	+ "signal instability_changed(value)\n" \
	+ "signal integrity_changed(value)\n" \
	+ "signal damaged(amount)\n" \
	+ "var display_name := \"Test Parcel\"\n" \
	+ "var instability := 0.0\n" \
	+ "var max_instability := 1.0\n" \
	+ "var integrity := 100.0\n" \
	+ "func get_max_integrity() -> float:\n\treturn 100.0\n"
const CARRIER_SRC := "extends Node3D\n" \
	+ "var carried = null\n" \
	+ "func get_carried_package():\n\treturn carried\n"

var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_resources()
	await _test_health_bar()
	await _test_defeat_burst()
	await _test_standalone_boot()
	await _test_combat_signals()
	await _test_enemy_binding()
	await _test_enemy_without_health()
	await _test_group_scan_and_cleanup()
	await _test_package_warnings()
	await _test_route_and_quest()
	await _test_preview()
	await _test_preview_auto_demo()

	print("\n=== Phase 4 integration visual tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -------------------------------------------------------------------

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


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _mock(source: String, node_name: String, spatial := false) -> Node:
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	_check(err == OK, "mock script %s compiles" % node_name)
	var node: Node = Node3D.new() if spatial else Node.new()
	node.set_script(script)
	node.name = node_name
	return node


func _presentation(auto_register := false) -> Node3D:
	var p := (load(PRESENTATION_SCENE) as PackedScene).instantiate() as Node3D
	p.set(&"auto_discover", false)
	p.set(&"auto_register_enemies", auto_register)
	return p


## Courier Node3D with mock CombatController + CombatHealth children.
func _courier() -> Node3D:
	var courier := Node3D.new()
	courier.name = "MockCourier"
	courier.add_child(_mock(CONTROLLER_SRC, "CombatController"))
	courier.add_child(_mock(HEALTH_SRC, "CombatHealth"))
	root.add_child(courier)
	return courier


func _enemy(enemy_name: String, at: Vector3, with_health := true) -> Node3D:
	var enemy := Node3D.new()
	enemy.name = enemy_name
	enemy.position = at
	if with_health:
		enemy.add_child(_mock(HEALTH_SRC, "CombatHealth"))
	return enemy


func _children_with_script(parent: Node, script: Script) -> Array[Node]:
	var found: Array[Node] = []
	for child in parent.get_children():
		if child.get_script() == script and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _enemy_visual_children(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var s: Script = child.get_script() as Script
		while s != null:
			if s == EnemyVisual:
				count += 1
				break
			s = s.get_base_script()
	return count


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await process_frame


# --- tests ---------------------------------------------------------------------

func _test_resources() -> void:
	print("[Resources]")
	for m in Assets.MATERIALS:
		var res: Resource = load(Assets.MATERIAL_DIR + m + ".tres")
		_check(res is StandardMaterial3D, "material %s loads as StandardMaterial3D" % m)
	var a := Assets.load_material("route_marker.tres", Color.RED)
	var b := Assets.load_material("route_marker.tres", Color.RED)
	_check(a != b and a.albedo_color.is_equal_approx(b.albedo_color), "load_material returns private copies")
	var t := Assets.tinted("route_marker.tres", Color(0.2, 0.4, 1.0, 0.5))
	_check(t.albedo_color.is_equal_approx(Color(0.2, 0.4, 1.0, 0.5)) and t.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "tinted copies recolour with alpha")
	var o := Assets.make_overlay(Assets.load_material("enemy_health_fill.tres", Color.GREEN), 12)
	_check(o.no_depth_test and o.render_priority == 12 and o.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "overlay material draws on top")
	for path in [PRESENTATION_SCENE, PREVIEW_SCENE]:
		var scene: Resource = load(path)
		_check(scene is PackedScene and (scene as PackedScene).can_instantiate(), "scene %s loads" % path.get_file())


func _test_health_bar() -> void:
	print("[Enemy health bar]")
	var bar: Node3D = HealthBar.new()
	bar.set(&"auto_animate", false)
	root.add_child(bar)
	await process_frame
	bar.call(&"set_health", 30.0, 30.0)
	var full: Color = bar.call(&"get_fill_color")
	_check(full.g > full.r, "full health reads green")
	bar.call(&"set_health", 15.0, 30.0)
	_check(is_equal_approx(float(bar.get(&"ratio")), 0.5) and is_equal_approx(float(bar.get(&"lag_ratio")), 1.0), "damage drops the fill, damage chunk holds")
	var fill := bar.get(&"fill_mesh") as MeshInstance3D
	_check(is_equal_approx(fill.scale.x, 0.5) and fill.position.x < -0.2, "fill shrinks from the right (x %.2f)" % fill.position.x)
	var half: Color = bar.call(&"get_fill_color")
	_check(half.r > 0.9 and half.g > 0.7, "half health reads yellow")
	bar.call(&"advance", 0.1)
	_check(is_equal_approx(float(bar.get(&"lag_ratio")), 1.0), "damage chunk waits for lag_delay")
	bar.call(&"advance", 0.3)
	bar.call(&"advance", 0.2)
	var lag := float(bar.get(&"lag_ratio"))
	_check(lag < 1.0 and lag >= 0.5, "damage chunk drains toward the fill (%.2f)" % lag)
	bar.call(&"play_hit")
	_check(is_equal_approx(float(bar.get(&"flash")), 1.0) and float(bar.get(&"shake")) > 0.9, "play_hit flashes and shakes")
	bar.call(&"advance", 0.5)
	_check(float(bar.get(&"flash")) < 0.01, "hit flash decays")

	var target := Node3D.new()
	root.add_child(target)
	target.global_position = Vector3(2, 0, 1)
	bar.set(&"follow_target", target)
	bar.call(&"advance", 0.01)
	_check(bar.global_position.is_equal_approx(Vector3(2, 1.4, 1)), "bar follows its enemy at follow_offset")

	var fades := [0]
	bar.connect(&"faded", func(): fades[0] += 1)
	bar.call(&"play_death")
	_check(bool(bar.get(&"dying")) and is_equal_approx(float(bar.get(&"ratio")), 0.0), "death empties the bar")
	bar.call(&"advance", 0.3)
	_check(bar.visible, "bar fades over fade_duration")
	bar.call(&"advance", 0.3)
	bar.call(&"advance", 0.3)
	_check(not bar.visible and fades[0] == 1 and bool(bar.call(&"is_faded")), "faded emitted once and bar hidden")
	bar.call(&"reset_bar")
	_check(bar.visible and is_equal_approx(float(bar.get(&"ratio")), 1.0) and not bool(bar.get(&"dying")), "reset_bar restores a full bar")
	await _free(target)
	await _free(bar)


func _test_defeat_burst() -> void:
	print("[Defeat burst VFX]")
	var burst: Node3D = DefeatBurst.new()
	burst.set(&"auto_animate", false)
	root.add_child(burst)
	burst.call(&"configure", Vector3(1, 0, 0), Color(0.5, 0.85, 1.0))
	var petals: Array = burst.get(&"petals")
	_check(petals.size() == 8 and burst.position.is_equal_approx(Vector3(1, 0, 0)), "burst has 8 petals at the configured spot")
	var p0 := (petals[0] as Node3D).position
	var ring := burst.get(&"ring") as Node3D
	var ring_start := ring.scale.x
	burst.call(&"advance", 0.3)
	_check(not (petals[0] as Node3D).position.is_equal_approx(p0) and ring.scale.x > ring_start, "petals fly out and the ring expands")
	var done := [0]
	burst.connect(&"finished", func(): done[0] += 1)
	burst.call(&"advance", 0.5)
	_check(done[0] == 1 and burst.is_queued_for_deletion(), "burst finishes and frees itself")
	await process_frame


func _test_standalone_boot() -> void:
	print("[Standalone boot: no gameplay]")
	var p := (load(PRESENTATION_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(p)
	await _frames(3)
	var adapter: Node = p.get(&"adapter")
	_check(bool(p.call(&"is_preview_mode")) and adapter.get(&"controller") == null, "boots in preview mode without errors")
	_check(adapter.get(&"hud") == p.get(&"combat_hud"), "reuses the Phase 4 combat HUD")
	var hud: Node = p.get(&"delivery_hud")
	var tracker := hud.get(&"tracker_panel") as Control
	_check(tracker != null and not tracker.visible and not bool(hud.call(&"is_banner_visible")), "delivery HUD built; tracker and banner stay hidden without a quest")
	_check((p.call(&"get_registered_enemies") as Array).is_empty(), "no enemies registered")
	_check(not bool((p.get(&"route") as Node).call(&"has_destination")), "no route until gameplay sets one")
	adapter.call(&"show_magic_bolt", Vector3(0, 1, 0), Vector3.FORWARD, 4.0)
	_check(_children_with_script(p.get(&"effects_root"), MagicBolt).size() == 1, "preview bolt spawns under the reused Effects root")
	await _free(p)


func _test_combat_signals() -> void:
	print("[Combat signals: bolt / dash / shield / package hits]")
	var courier := _courier()
	var controller := courier.get_node("CombatController")
	var health := courier.get_node("CombatHealth")
	var p := _presentation()
	root.add_child(p)
	await process_frame
	var effects: Node = p.get(&"effects_root")
	var hud: Node = p.get(&"delivery_hud")
	var combat_hud: Node = p.get(&"combat_hud")
	var modes := []
	p.connect(&"binding_changed", func(v): modes.append(v))

	_check(bool(p.call(&"bind_controller", controller)), "bind_controller connects by signal name")
	_check(not bool(p.call(&"is_preview_mode")) and modes == [false], "binding leaves preview mode and is relayed")
	_check(p.call(&"get_actor") == courier and (p.get(&"adapter") as Node).get(&"player_health") == health, "actor and sibling CombatHealth discovered")

	controller.emit_signal(&"magic_bolt_fired", Vector3(0, 1, 0), Vector3(0, 0, -1))
	_check(_children_with_script(effects, MagicBolt).size() == 1, "magic_bolt_fired -> Magic Bolt VFX")
	controller.emit_signal(&"dash_started")
	courier.global_position = Vector3(2, 0, 0)
	controller.emit_signal(&"dash_finished")
	_check(_children_with_script(effects, DashVfx).size() == 1, "dash -> afterimage trail VFX")

	health.emit_signal(&"health_changed", 60, 100)
	_check((combat_hud.get(&"health_label") as Label).text == "HP 60 / 100", "player health_changed -> combat HUD")
	health.emit_signal(&"damaged", 15, Vector3.ZERO)
	_check(String(hud.call(&"get_alert_text")) == "Package hit! -15" and bool(hud.call(&"is_banner_visible")), "unshielded courier hit -> package hit warning")

	controller.emit_signal(&"shield_changed", true, 0.8)
	var shield: Node3D = (p.get(&"adapter") as Node).get(&"shield_vfx")
	_check(shield != null and bool(shield.call(&"is_shown")) and bool(p.get(&"shield_active")), "shield_changed -> package shield bubble")
	health.emit_signal(&"damaged", 10, Vector3.ZERO)
	_check(String(hud.call(&"get_alert_text")) == "Shield absorbed the hit", "shielded hit reads as absorbed")
	controller.emit_signal(&"shield_changed", true, 0.2)
	_check(String(hud.call(&"get_alert_text")) == "Shield cracking", "low shield durability warns")
	controller.emit_signal(&"shield_changed", false, 0.0)
	_check(String(hud.call(&"get_alert_text")) == "Shield broken!", "shield break warns")

	p.set(&"warn_without_package", false)
	hud.call(&"advance", 5.0)
	health.emit_signal(&"damaged", 5, Vector3.ZERO)
	_check(String(hud.call(&"get_alert_text")) == "", "warn_without_package=false suppresses alerts without a package")
	await _free(p)
	await _free(courier)


func _test_enemy_binding() -> void:
	print("[Enemy registration, hit and death feedback]")
	var courier := _courier()
	var controller := courier.get_node("CombatController")
	var p := _presentation()
	root.add_child(p)
	await process_frame
	p.call(&"bind_controller", controller)
	var effects: Node = p.get(&"effects_root")

	var enemy := _enemy("FrostWispScout", Vector3(0, 0, -3))
	root.add_child(enemy)
	await process_frame
	var health := enemy.get_node("CombatHealth")
	var registered := []
	p.connect(&"enemy_registered", func(e, _v): registered.append(e))
	var visual: Node = p.call(&"register_enemy", enemy)
	_check(visual != null and visual.get_script() == WispScript and visual.get_parent() == enemy, "frost wisp visual instanced under the enemy (kind from name)")
	_check(p.call(&"get_enemy_kind", enemy) == &"frost_wisp" and registered == [enemy], "enemy_registered emitted with kind frost_wisp")
	_check(p.call(&"register_enemy", enemy) == visual and _enemy_visual_children(enemy) == 1, "registering twice is a no-op")
	_check(visual.call(&"get_bound_health") == health, "enemy visual bound to its CombatHealth")
	var bar: Node3D = p.call(&"get_enemy_bar", enemy)
	_check(bar != null and bar.get_parent() == p.get(&"bars_root") and is_equal_approx(float(bar.get(&"ratio")), 1.0), "health bar created from current_health / max_health")

	health.emit_signal(&"health_changed", 15, 30)
	_check(is_equal_approx(float(bar.get(&"ratio")), 0.5), "enemy health_changed -> bar at 50%")
	await process_frame
	_check(bar.global_position.distance_to(enemy.global_position + Vector3(0, 2.05, 0)) < 0.01, "bar floats above the wisp")

	var numbers := _children_with_script(effects, DamageNumber).size()
	var hits := [0]
	visual.connect(&"hit_played", func(_src): hits[0] += 1)
	health.emit_signal(&"damaged", 5, Vector3(0, 1, 0))
	_check(int(visual.get(&"state")) == S.HIT and float(bar.get(&"flash")) > 0.9, "enemy damaged -> hit animation + bar flash")
	await process_frame
	_check(_children_with_script(effects, DamageNumber).size() == numbers + 1, "damaged without target_hit -> one damage number")
	health.emit_signal(&"damaged", 5, Vector3(0, 1, 0))
	controller.emit_signal(&"target_hit", enemy, 5)
	await process_frame
	_check(_children_with_script(effects, DamageNumber).size() == numbers + 2, "damaged + target_hit in one frame -> no duplicate number")
	_check(hits[0] == 2, "health-bound enemy plays one hit per damage, not per target_hit (%d)" % hits[0])

	var defeated := []
	p.connect(&"enemy_defeated", func(e): defeated.append(e))
	health.emit_signal(&"died")
	_check(int(visual.get(&"state")) == S.DEAD and bool(bar.get(&"dying")), "died -> death animation + bar fades")
	_check(defeated == [enemy] and int(p.get(&"defeated_count")) == 1 and int(p.call(&"get_living_enemy_count")) == 0, "enemy_defeated emitted once")
	_check(_children_with_script(effects, DefeatBurst).size() == 1, "defeat burst spawned in Effects")
	health.emit_signal(&"died")
	_check(defeated.size() == 1, "repeated died is ignored")
	health.emit_signal(&"health_changed", 30, 30)
	_check(int(visual.get(&"state")) == S.IDLE and not bool(bar.get(&"dying")) and is_equal_approx(float(bar.get(&"ratio")), 1.0), "health restored -> enemy and bar revive")

	var blob := _enemy("Blob", Vector3(2, 0, -2))
	blob.set_meta(&"enemy_kind", "forest_slime")
	root.add_child(blob)
	var bandit := _enemy("Bandit", Vector3(-2, 0, -2))
	root.add_child(bandit)
	await process_frame
	var blob_visual: Node = p.call(&"register_enemy", blob)
	var bandit_visual: Node = p.call(&"register_enemy", bandit, &"frost_wisp")
	_check(blob_visual.get_script() == SlimeScript, "enemy_kind meta selects the forest slime")
	_check(bandit_visual.get_script() == WispScript, "explicit kind argument wins")

	var unregistered := []
	p.connect(&"enemy_unregistered", func(e): unregistered.append(e))
	p.call(&"unregister_enemy", blob)
	await process_frame
	_check(unregistered == [blob] and not is_instance_valid(blob_visual) and _enemy_visual_children(blob) == 0, "unregister frees the owned visual")
	_check(blob.get_node("CombatHealth").get_signal_connection_list(&"died").is_empty(), "unregister disconnects enemy health")
	await _free(blob)
	await _free(bandit)
	await _free(enemy)
	await _free(p)
	await _free(courier)


func _test_enemy_without_health() -> void:
	print("[Enemy without CombatHealth: target_hit only]")
	var courier := _courier()
	var controller := courier.get_node("CombatController")
	var p := _presentation()
	root.add_child(p)
	await process_frame
	p.call(&"bind_controller", controller)
	var dummy := _enemy("SlimeDummy", Vector3(0, 0, -2), false)
	root.add_child(dummy)
	await process_frame
	var visual: Node = p.call(&"register_enemy", dummy)
	var bar: Node3D = p.call(&"get_enemy_bar", dummy)
	_check(visual != null and visual.get_script() == SlimeScript and visual.call(&"get_bound_health") == null, "health-less enemy still gets a slime visual")
	controller.emit_signal(&"target_hit", dummy, 0.25)
	_check(int(visual.get(&"state")) == S.HIT, "target_hit plays the hit animation via the adapter")
	_check(float(bar.get(&"ratio")) < 1.0 and float(bar.get(&"flash")) > 0.9, "target_hit drives the bar when no health is bound")
	await _free(dummy)
	await _free(p)
	await _free(courier)


func _test_group_scan_and_cleanup() -> void:
	print("[Enemy group scan, visual reuse, cleanup]")
	var first := _enemy("ForestSlimeA", Vector3(1, 0, -4))
	var existing := (load(SLIME_SCENE) as PackedScene).instantiate()
	existing.name = "GameplayVisual"
	first.add_child(existing)
	first.add_to_group(&"enemies")
	root.add_child(first)
	var p := _presentation(true)
	p.set(&"scan_interval", 0.1)
	root.add_child(p)
	await _frames(3)
	_check((p.call(&"get_registered_enemies") as Array).size() == 1, "group member auto-registered")
	_check(p.call(&"get_enemy_visual", first) == existing and _enemy_visual_children(first) == 1, "existing enemy visual reused, not duplicated")

	var second := _enemy("Wisp2", Vector3(-1, 0, -5))
	second.add_to_group(&"enemies")
	root.add_child(second)
	await _wait(0.3)
	_check((p.call(&"get_registered_enemies") as Array).size() == 2, "late spawns picked up by the periodic scan")
	var hud: Node = p.get(&"delivery_hud")
	_check(int(hud.get(&"threats")) == 2, "quest tracker counts living threats")

	var bar: Node3D = p.call(&"get_enemy_bar", second)
	second.queue_free()
	await _frames(3)
	_check((p.call(&"get_registered_enemies") as Array).size() == 1 and not is_instance_valid(bar), "freed enemy is pruned with its bar")
	p.call(&"unregister_enemy", first)
	await process_frame
	_check(is_instance_valid(existing), "gameplay-owned visual is never freed by the layer")
	await _free(p)
	await _free(first)


func _test_package_warnings() -> void:
	print("[Package warnings]")
	var p := _presentation()
	root.add_child(p)
	await process_frame
	var hud: Node = p.get(&"delivery_hud")
	var pkg := _mock(PACKAGE_SRC, "Parcel")
	root.add_child(pkg)
	var levels := []
	p.connect(&"package_warning_changed", func(l): levels.append(l))
	p.call(&"bind_package", pkg)
	_check(hud.call(&"get_bound_package") == pkg and int(hud.call(&"get_warning_level")) == 0 and not bool(hud.call(&"is_banner_visible")), "healthy package shows no banner")

	pkg.set(&"instability", 0.9)
	pkg.emit_signal(&"instability_changed", 0.9)
	_check(int(hud.call(&"get_warning_level")) == 2 and String(hud.call(&"get_warning_text")).contains("VOLATILE"), "volatile package -> CRITICAL banner")
	_check(String(hud.call(&"get_banner_text")).begins_with("Test Parcel:"), "banner names the package")
	pkg.set(&"instability", 0.0)
	pkg.emit_signal(&"instability_changed", 0.0)
	pkg.set(&"integrity", 40.0)
	pkg.emit_signal(&"integrity_changed", 40.0)
	_check(int(hud.call(&"get_warning_level")) == 1 and String(hud.call(&"get_warning_text")).contains("Damaged 40%"), "integrity 40% -> CAUTION")
	pkg.set(&"integrity", 20.0)
	pkg.emit_signal(&"integrity_changed", 20.0)
	_check(int(hud.call(&"get_warning_level")) == 2 and String(hud.call(&"get_warning_text")).contains("BREAKING"), "integrity 20% -> CRITICAL")
	pkg.emit_signal(&"damaged", 5)
	_check(String(hud.call(&"get_banner_text")) == "Package damaged! -5", "package damaged signal -> transient alert")
	hud.call(&"advance", 2.0)
	_check(String(hud.call(&"get_alert_text")) == "" and String(hud.call(&"get_banner_text")).contains("BREAKING"), "alert expires back to the persistent warning")
	_check(levels.has(2) and levels.has(1), "package_warning_changed relayed (%s)" % [levels])
	p.call(&"unbind_package")
	_check(int(hud.call(&"get_warning_level")) == 0 and not bool(hud.call(&"is_banner_visible")), "unbinding clears the banner")

	var carrier := _mock(CARRIER_SRC, "Carrier", true)
	carrier.set(&"carried", pkg)
	root.add_child(carrier)
	p.call(&"set_actor", carrier)
	_check(hud.call(&"get_bound_package") == pkg, "package auto-discovered via get_carried_package()")
	await _free(p)
	await _free(carrier)
	await _free(pkg)


func _test_route_and_quest() -> void:
	print("[Forest route + quest indicators]")
	var p := _presentation()
	root.add_child(p)
	await process_frame
	var route: Node3D = p.get(&"route")
	var hud: Node = p.get(&"delivery_hud")
	route.set(&"auto_animate", false)
	p.call(&"set_route", PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -10), Vector3(6, 0, -10)]))
	var count := int(route.call(&"get_marker_count"))
	_check(count >= 8 and count <= 64, "route markers laid along the path (%d)" % count)
	_check((route.get(&"flowers") as Array).size() > 0, "flower tufts decorate the verge")
	var c0: Color = route.call(&"get_marker_color", 0)
	var c1: Color = route.call(&"get_marker_color", count - 1)
	_check(not c0.is_equal_approx(c1) and c0.g > c0.b, "markers shift colour along the route (%s -> %s)" % [c0, c1])
	var beacon: Node3D = route.get(&"beacon")
	_check(bool(route.call(&"has_destination")) and beacon.visible and (route.get(&"beacon_label") as Label3D).text == "Drop-off", "route end becomes the quest beacon")
	p.call(&"set_destination", Vector3(6, 0, -10), "Moonwell Shrine")
	_check((route.get(&"beacon_label") as Label3D).text == "Moonwell Shrine", "destination label set")
	p.call(&"set_quest", "Moonpetal Delivery", "Reach the shrine.")
	_check((hud.get(&"title_label") as Label).text == "Moonpetal Delivery", "quest tracker shows the title")

	var actor := Node3D.new()
	root.add_child(actor)
	actor.global_position = Vector3(0, 0, -5)
	p.call(&"set_actor", actor)
	await process_frame
	_check(int(route.get(&"progress_index")) > 0 and (route.call(&"get_marker_color", 0) as Color).a < 0.5, "markers behind the courier dim")
	_check(String(hud.call(&"get_distance_text")) == "8 m to drop-off", "tracker distance ('%s')" % hud.call(&"get_distance_text"))
	var ratio := float(hud.call(&"get_progress_ratio"))
	_check(ratio > 0.3 and ratio < 0.8, "route progress strip (%.2f)" % ratio)
	actor.global_position = Vector3(6, 0, -9)
	await process_frame
	_check(String(hud.call(&"get_distance_text")).begins_with("Arrived"), "arrival within arrive_radius")

	p.call(&"set_quest_state", &"complete")
	var gem: Color = route.call(&"get_beacon_color")
	_check(gem.g > gem.r and gem.g > gem.b and String(hud.call(&"get_distance_text")) == "Delivered!", "complete turns the beacon green")
	var marker: Node3D = p.call(&"add_quest_marker", &"pickup", Vector3(3, 0, 0), "Herbalist")
	_check(marker != null and marker.is_inside_tree() and marker.get_node_or_null("Gem") != null, "quest marker pinned")
	p.call(&"remove_quest_marker", &"pickup")
	await process_frame
	_check(not is_instance_valid(marker), "quest marker removed")
	p.call(&"set_quest_state", &"hidden")
	_check(not route.visible and not (hud.get(&"tracker_panel") as Control).visible, "hidden quest hides route and tracker")

	route.set(&"max_markers", 10)
	p.call(&"set_route", PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -100)]))
	_check(int(route.call(&"get_marker_count")) <= 10, "marker count capped by max_markers")
	await _free(actor)
	await _free(p)


func _test_preview() -> void:
	print("[Standalone preview scene]")
	var preview := (load(PREVIEW_SCENE) as PackedScene).instantiate() as Node3D
	preview.set(&"auto_demo", false)
	root.add_child(preview)
	current_scene = preview
	await _frames(5)
	var p: Node3D = preview.get(&"presentation")
	var hud: Node = p.get(&"delivery_hud")
	var combat_hud: Node = p.get(&"combat_hud")
	var enemies: Array = p.call(&"get_registered_enemies")
	var slimes := 0
	var wisps := 0
	for e in enemies:
		slimes += 1 if p.call(&"get_enemy_kind", e) == &"forest_slime" else 0
		wisps += 1 if p.call(&"get_enemy_kind", e) == &"frost_wisp" else 0
	_check(slimes == 2 and wisps == 2, "preview registers 2 slimes and 2 wisps through the group scan")
	_check(not bool(p.call(&"is_preview_mode")), "presentation bound to the preview stand-ins by signal name")
	_check(int((p.get(&"route") as Node).call(&"get_marker_count")) > 0 and (hud.get(&"title_label") as Label).text == "Moonpetal Delivery", "route and quest tracker set up")
	_check((combat_hud.get(&"health_label") as Label).text == "HP 100 / 100", "combat HUD shows full courier health")
	_check((preview.get(&"help_label") as Label).text.contains("[1] Magic Bolt"), "help overlay lists preview keys")

	var target: Node3D = preview.call(&"_nearest_living_enemy")
	_check(bool(preview.call(&"trigger_preview", &"bolt")), "preview bolt fires")
	_check(_children_with_script(p.get(&"effects_root"), MagicBolt).size() == 1, "bolt VFX spawned")
	_check(not bool(preview.call(&"trigger_preview", &"bolt")), "bolt respects the stand-in cooldown")
	await _wait(0.8)
	var bar: Node3D = p.call(&"get_enemy_bar", target)
	_check(is_equal_approx(float(preview.call(&"get_enemy_hp", target)), 20.0) and float(bar.get(&"ratio")) < 0.7, "bolt impact damages the nearest enemy and its bar")
	for i in 2:
		preview.call(&"trigger_preview", &"bolt")
		await _wait(0.75)
	_check(int(p.call(&"get_living_enemy_count")) == 3 and int(p.get(&"defeated_count")) == 1, "three bolts defeat the enemy")

	preview.call(&"trigger_preview", &"hurt")
	_check(String(hud.call(&"get_alert_text")).begins_with("Package") and (combat_hud.get(&"health_label") as Label).text == "HP 85 / 100", "unshielded hit warns about the package")
	preview.call(&"trigger_preview", &"shield")
	preview.call(&"trigger_preview", &"hurt")
	_check(String(hud.call(&"get_alert_text")) == "Shield absorbed the hit" and (combat_hud.get(&"health_label") as Label).text == "HP 85 / 100", "shielded hit absorbed")
	for i in 3:
		preview.call(&"trigger_preview", &"heat")
	_check(int(hud.call(&"get_warning_level")) == 2, "heated, unstable package -> CRITICAL warning")

	var courier: Node3D = preview.get(&"courier")
	var start := courier.global_position
	_check(bool(preview.call(&"trigger_preview", &"advance")) and not courier.global_position.is_equal_approx(start), "advance moves the courier along the route")
	await process_frame
	_check(String(hud.call(&"get_distance_text")).ends_with("m to drop-off"), "tracker distance updates ('%s')" % hud.call(&"get_distance_text"))
	for i in 3:
		preview.call(&"trigger_preview", &"advance")
	_check((p.get(&"route") as Node).get(&"quest_state") == &"complete" and not bool(preview.call(&"trigger_preview", &"advance")), "reaching the shrine completes the quest")

	_check(bool(preview.call(&"trigger_preview", &"reset")), "preview reset")
	await process_frame
	_check(int(p.call(&"get_living_enemy_count")) == 4 and (p.get(&"route") as Node).get(&"quest_state") == &"active" and (combat_hud.get(&"health_label") as Label).text == "HP 100 / 100", "reset revives enemies, quest and health")
	current_scene = null
	await _free(preview)


func _test_preview_auto_demo() -> void:
	print("[Preview auto demo]")
	var preview := (load(PREVIEW_SCENE) as PackedScene).instantiate() as Node3D
	preview.set(&"demo_interval", 0.05)
	root.add_child(preview)
	current_scene = preview
	await _wait(0.6)
	_check(int(preview.get(&"_demo_step")) >= 3 and String(preview.get(&"last_action")) != "", "auto demo cycles preview actions (step %d)" % int(preview.get(&"_demo_step")))
	current_scene = null
	await _free(preview)
