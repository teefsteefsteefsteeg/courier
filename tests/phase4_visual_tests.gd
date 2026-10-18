extends SceneTree
## Phase 4 visual slice automated checks (enemy models + animation states, combat
## VFX, combat HUD, gameplay signal adapter, forest encounter showcase).
##   godot --headless --path . --script res://tests/phase4_visual_tests.gd
## Exit code = number of failed checks. Independent of gameplay combat code:
## gameplay nodes are mocked with runtime GDScript that exposes the contract signals.

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const EnemyVisual := preload("res://scripts/phase4_visual/enemy_visual.gd")
const MagicBolt := preload("res://scripts/phase4_visual/magic_bolt_vfx.gd")
const DashVfx := preload("res://scripts/phase4_visual/dash_vfx.gd")
const ShieldVfx := preload("res://scripts/phase4_visual/package_shield_vfx.gd")
const DamageNumber := preload("res://scripts/phase4_visual/damage_number_vfx.gd")
const SLIME_SCENE := "res://scenes/phase4_visual/enemies/forest_slime.tscn"
const WISP_SCENE := "res://scenes/phase4_visual/enemies/frost_wisp.tscn"
const HUD_SCENE := "res://scenes/phase4_visual/ui/combat_hud.tscn"
const LAYER_SCENE := "res://scenes/gameplay/phase4_visual/combat_visual_layer.tscn"
const SHOWCASE_SCENE := "res://scenes/phase4_visual/forest_encounter_showcase.tscn"
const SCENES := [
	SLIME_SCENE, WISP_SCENE, HUD_SCENE, LAYER_SCENE, SHOWCASE_SCENE,
	"res://scenes/phase4_visual/vfx/magic_bolt_vfx.tscn",
	"res://scenes/phase4_visual/vfx/dash_vfx.tscn",
	"res://scenes/phase4_visual/vfx/package_shield_vfx.tscn",
	"res://scenes/phase4_visual/vfx/damage_number_vfx.tscn",
]
const MATERIALS := [
	"forest_slime_body", "forest_slime_core", "forest_slime_leaf", "creature_eye",
	"frost_wisp_core", "frost_wisp_shell", "frost_wisp_shard", "magic_bolt",
	"magic_bolt_glow", "impact_spark", "dash_afterimage", "package_shield",
	"forest_ground", "tree_bark", "tree_leaves", "forest_rock",
]
const ENEMY_TRIANGLE_BUDGET := 600
const S := EnemyVisual.State

const CONTROLLER_SRC := "extends Node\n" \
	+ "signal magic_bolt_fired(origin, direction)\n" \
	+ "signal dash_started\n" \
	+ "signal dash_finished\n" \
	+ "signal shield_changed(active, durability)\n" \
	+ "signal target_hit(target, amount)\n" \
	+ "var bolt_remaining := 0.0\n" \
	+ "func get_bolt_cooldown_remaining() -> float:\n\treturn bolt_remaining\n" \
	+ "func get_bolt_cooldown() -> float:\n\treturn 0.5\n"
const HEALTH_SRC := "extends Node\n" \
	+ "signal health_changed(current, maximum)\n" \
	+ "signal damaged(amount, source_position)\n" \
	+ "signal died\n"

var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_resources()
	_test_lowpoly()
	await _test_forest_slime()
	await _test_frost_wisp()
	await _test_health_binding()
	await _test_magic_bolt()
	await _test_dash()
	await _test_shield()
	await _test_damage_number()
	await _test_hud()
	await _test_adapter_preview()
	await _test_adapter_gameplay()
	await _test_adapter_auto_discovery()
	await _test_showcase()
	await _test_showcase_auto_demo()

	print("\n=== Phase 4 visual tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _spawn(path: String) -> Node:
	var node := (load(path) as PackedScene).instantiate()
	root.add_child(node)
	return node


func _mock(source: String, node_name: String) -> Node:
	var script := GDScript.new()
	script.source_code = source
	var err := script.reload()
	_check(err == OK, "mock script %s compiles" % node_name)
	var node := Node.new()
	node.set_script(script)
	node.name = node_name
	return node


func _children_with_script(parent: Node, script: Script) -> Array[Node]:
	var found: Array[Node] = []
	for child in parent.get_children():
		if child.get_script() == script and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await process_frame


# --- tests ---------------------------------------------------------------------

func _test_resources() -> void:
	print("[Resources]")
	for m in MATERIALS:
		var res: Resource = load(Lowpoly.MATERIAL_DIR + m + ".tres")
		_check(res is StandardMaterial3D, "material %s loads as StandardMaterial3D" % m)
	var a := Lowpoly.load_material("forest_slime_body.tres", Color.RED)
	var b := Lowpoly.load_material("forest_slime_body.tres", Color.RED)
	_check(a != b and a.albedo_color.is_equal_approx(b.albedo_color), "load_material returns private copies")
	_check(a.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "slime jelly is translucent")
	for path in SCENES:
		var scene: Resource = load(path)
		_check(scene is PackedScene and (scene as PackedScene).can_instantiate(), "scene %s loads" % path.get_file())


func _test_lowpoly() -> void:
	print("[Low-poly meshes]")
	var s := Lowpoly.sphere(0.5, 1.0, 8, 4)
	var tris := Lowpoly.triangle_count(s)
	_check(tris >= 48 and tris <= 80, "8x4 faceted sphere has %d triangles (48..80)" % tris)
	_check(Lowpoly.triangle_count(Lowpoly.box(Vector3.ONE)) == 12, "faceted box has 12 triangles")
	_check(s.get_surface_count() == 1, "faceted mesh has one surface")


func _test_forest_slime() -> void:
	print("[Forest Slime]")
	var slime := _spawn(SLIME_SCENE) as Node3D
	slime.set(&"auto_animate", false)
	await process_frame
	var body: Node3D = slime.get(&"body")
	_check(body != null, "slime builds its animated body pivot")
	for part in ["Jelly", "SeedCore", "EyeL", "EyeR", "Sprout"]:
		_check(body.get_node_or_null(part) != null, "slime has part %s" % part)
	var tris := int(slime.get(&"triangle_count"))
	_check(tris >= 40 and tris <= ENEMY_TRIANGLE_BUDGET, "slime is low-poly: %d triangles (budget %d)" % [tris, ENEMY_TRIANGLE_BUDGET])

	var states := []
	slime.connect(&"state_changed", func(n, _o): states.append(n))
	_check(int(slime.get(&"state")) == S.IDLE, "slime starts IDLE")
	var scale_a := body.scale
	slime.call(&"advance", 0.25)
	_check(not body.scale.is_equal_approx(scale_a), "idle breathing changes body scale")

	slime.call(&"play_move")
	slime.call(&"advance", 0.2)
	_check(int(slime.get(&"state")) == S.MOVE and body.position.y > 0.05, "move hops (height %.2f)" % body.position.y)

	var jelly := body.get_node("Jelly") as MeshInstance3D
	var jelly_mat := jelly.material_override as StandardMaterial3D
	var base_color := jelly_mat.albedo_color
	slime.call(&"play_hit", slime.global_position + Vector3(2, 0, 0))
	_check(int(slime.get(&"state")) == S.HIT and is_equal_approx(float(slime.get(&"flash_amount")), 1.0), "play_hit enters HIT with full flash")
	slime.call(&"advance", 0.15)
	_check(not jelly_mat.albedo_color.is_equal_approx(base_color), "hit flash tints the jelly")
	_check(body.position.x < -0.05, "hit knocks the slime away from the source (x %.2f)" % body.position.x)
	slime.call(&"advance", 0.3)
	_check(int(slime.get(&"state")) == S.MOVE, "hit returns to the interrupted MOVE state")

	var deaths := [0]
	slime.connect(&"death_finished", func(): deaths[0] += 1)
	slime.call(&"play_death")
	slime.call(&"play_hit", Vector3.ZERO)
	_check(int(slime.get(&"state")) == S.DEAD, "hits are ignored once dead")
	slime.call(&"advance", 0.45)
	_check(body.scale.y < 0.5 and body.scale.x > 1.0, "death melts into a puddle (scale %s)" % body.scale)
	for i in 6:
		slime.call(&"advance", 0.2)
	_check(deaths[0] == 1 and not slime.visible, "death_finished emitted once and slime hidden")
	slime.call(&"play_move")
	_check(int(slime.get(&"state")) == S.DEAD, "dead slime ignores play_move")
	slime.call(&"reset_visual")
	_check(int(slime.get(&"state")) == S.IDLE and slime.visible and jelly_mat.albedo_color.a > 0.8, "reset_visual restores an idle, opaque slime")
	_check(states == [S.MOVE, S.HIT, S.MOVE, S.DEAD, S.IDLE], "state_changed sequence %s" % [states])
	await _free(slime)


func _test_frost_wisp() -> void:
	print("[Frost Wisp]")
	var wisp := _spawn(WISP_SCENE) as Node3D
	wisp.set(&"auto_animate", false)
	await process_frame
	var body: Node3D = wisp.get(&"body")
	for part in ["Core", "Shell", "Tail", "FrostGlow", "Shard0", "Shard3"]:
		_check(body.get_node_or_null(part) != null, "wisp has part %s" % part)
	var tris := int(wisp.get(&"triangle_count"))
	_check(tris >= 40 and tris <= ENEMY_TRIANGLE_BUDGET, "wisp is low-poly: %d triangles (budget %d)" % [tris, ENEMY_TRIANGLE_BUDGET])
	wisp.call(&"advance", 0.1)
	_check(absf(body.position.y - 1.15) < 0.2, "wisp hovers (height %.2f)" % body.position.y)
	var shard := body.get_node("Shard0") as Node3D
	var p0 := shard.position
	wisp.call(&"advance", 0.3)
	_check(not shard.position.is_equal_approx(p0), "shards orbit while idle")
	var resting_radius := float(wisp.call(&"get_orbit_radius"))

	wisp.call(&"play_move")
	wisp.call(&"advance", 0.1)
	_check(body.rotation.x < -0.3, "move leans the wisp forward (%.2f rad)" % body.rotation.x)
	wisp.call(&"play_hit", wisp.global_position + Vector3(0, 0, 3))
	wisp.call(&"advance", 0.05)
	_check(float(wisp.call(&"get_orbit_radius")) > resting_radius + 0.1, "hit scatters the shards outward")
	wisp.call(&"advance", 0.4)
	_check(int(wisp.get(&"state")) == S.MOVE, "wisp resumes MOVE after hit")

	var deaths := [0]
	wisp.connect(&"death_finished", func(): deaths[0] += 1)
	wisp.call(&"play_death")
	var y_before := body.position.y
	wisp.call(&"advance", 0.6)
	_check(float(wisp.call(&"get_orbit_radius")) > resting_radius * 2.0 and body.position.y < y_before, "death shatters shards outward and drops the core")
	wisp.call(&"advance", 0.6)
	_check(deaths[0] == 1 and not wisp.visible, "wisp death_finished emitted once")
	await _free(wisp)


func _test_health_binding() -> void:
	print("[Enemy CombatHealth binding]")
	var slime := _spawn(SLIME_SCENE) as Node3D
	slime.set(&"auto_animate", false)
	var health := _mock(HEALTH_SRC, "EnemyHealth")
	root.add_child(health)
	await process_frame
	_check(bool(slime.call(&"bind_health", health)), "bind_health connects by signal name")
	health.emit_signal(&"damaged", 5, Vector3(1, 0, 0))
	_check(int(slime.get(&"state")) == S.HIT, "damaged -> play_hit")
	health.emit_signal(&"died")
	_check(int(slime.get(&"state")) == S.DEAD, "died -> play_death")
	slime.call(&"unbind_health")
	_check(not health.is_connected(&"damaged", Callable(slime, "_on_health_damaged")), "unbind_health disconnects")
	var plain := Node.new()
	_check(not bool(slime.call(&"bind_health", plain)), "binding a node without health signals is a safe no-op")
	plain.free()
	await _free(health)
	await _free(slime)


func _test_magic_bolt() -> void:
	print("[Magic bolt VFX]")
	var bolt: Node3D = MagicBolt.new()
	bolt.set(&"auto_animate", false)
	root.add_child(bolt)
	bolt.call(&"configure", Vector3(0, 1, 0), Vector3(0, 0, -2), 6.0)
	var hits := []
	var done := [0]
	bolt.connect(&"impacted", func(p): hits.append(p))
	bolt.connect(&"finished", func(): done[0] += 1)
	bolt.call(&"advance", 0.1)
	var head: Vector3 = bolt.call(&"get_head_position")
	_check(head.is_equal_approx(Vector3(0, 1, -1.6)), "bolt travels along direction at speed (%s)" % head)
	var trail: Array = bolt.get(&"trail")
	_check(trail.size() == 6 and (trail[0] as Node3D).position.is_equal_approx(head), "trail follows the head")
	_check(hits.is_empty(), "no impact mid-flight")
	for i in 4:
		bolt.call(&"advance", 0.1)
	var impact_at: Vector3 = hits[0] if hits.size() == 1 else Vector3.INF
	_check(impact_at.is_equal_approx(Vector3(0, 1, -6)), "impact at max distance (%s)" % [hits])
	_check((bolt.get(&"burst") as Node3D).visible and not (bolt.get(&"head") as Node3D).visible, "impact swaps head for burst")
	bolt.call(&"advance", 0.4)
	_check(done[0] == 1 and bolt.is_queued_for_deletion(), "bolt finishes and frees itself")
	await process_frame

	var early: Node3D = MagicBolt.new()
	early.set(&"auto_animate", false)
	root.add_child(early)
	early.call(&"configure", Vector3.ZERO, Vector3.RIGHT, 10.0)
	early.call(&"advance", 0.05)
	early.call(&"impact", Vector3(0.5, 0, 0))
	var early_head: Vector3 = early.call(&"get_head_position")
	_check(bool(early.get(&"has_impacted")) and early_head.is_equal_approx(Vector3(0.5, 0, 0)), "impact() ends flight early at the given point")
	await _free(early)


func _test_dash() -> void:
	print("[Dash VFX]")
	var dash: Node3D = DashVfx.new()
	dash.set(&"auto_animate", false)
	root.add_child(dash)
	dash.call(&"configure", Vector3.ZERO, Vector3(3, 0, 0))
	var ghosts: Array = dash.get(&"ghosts")
	_check(ghosts.size() == 4, "4 afterimages spawned")
	var between := true
	for g in ghosts:
		var x := (g as Node3D).position.x
		between = between and x > 0.0 and x < 3.0
	_check(between, "afterimages lie along the dash path")
	_check(dash.get_node_or_null("WindStreak") != null and dash.get_node_or_null("ArrivalPuff") != null, "streak and arrival puff present")
	var alpha_start := float(dash.call(&"get_ghost_alpha", 3))
	dash.call(&"advance", 0.2)
	var oldest := float(dash.call(&"get_ghost_alpha", 0))
	var newest := float(dash.call(&"get_ghost_alpha", 3))
	_check(newest < alpha_start and oldest <= newest, "afterimages fade, oldest first (%.2f <= %.2f)" % [oldest, newest])
	var done := [0]
	dash.connect(&"finished", func(): done[0] += 1)
	dash.call(&"advance", 0.3)
	_check(done[0] == 1 and dash.is_queued_for_deletion(), "dash VFX finishes and frees itself")
	await process_frame


func _test_shield() -> void:
	print("[Package shield VFX]")
	var shield: Node3D = ShieldVfx.new()
	shield.set(&"auto_animate", false)
	root.add_child(shield)
	await process_frame
	var shows := []
	shield.connect(&"shield_visibility_changed", func(v): shows.append(v))
	_check(not shield.visible, "shield hidden by default")
	shield.call(&"set_shield", true, 1.0)
	shield.call(&"advance", 0.3)
	_check(shield.visible and bool(shield.call(&"is_shown")) and is_equal_approx(float(shield.call(&"get_presence")), 1.0), "activation raises the bubble")
	var full: Color = shield.call(&"get_current_color")
	_check(full.g > full.r, "full durability reads teal")
	shield.call(&"set_shield", true, 0.25)
	_check(float(shield.get(&"crack_flash")) > 0.9, "durability loss flashes the bubble")
	shield.call(&"advance", 0.5)
	var low: Color = shield.call(&"get_current_color")
	_check(low.r > low.g and low.a < full.a, "low durability reads ember and thinner")
	shield.call(&"set_shield", true, 50.0)
	_check(is_equal_approx(float(shield.get(&"durability")), 0.5), "raw points above 1 are scaled by durability_scale")

	var anchor := Node3D.new()
	root.add_child(anchor)
	anchor.global_position = Vector3(3, 0, 0)
	shield.set(&"follow_target", anchor)
	shield.call(&"advance", 0.01)
	_check(shield.global_position.is_equal_approx(Vector3(3, 0.9, 0)), "shield follows the package carrier")

	shield.call(&"set_shield", false, 0.5)
	shield.call(&"advance", 0.15)
	_check(shield.visible, "deactivation collapses over time")
	shield.call(&"advance", 0.2)
	_check(not shield.visible and shows == [true, false], "fully collapsed shield hides (%s)" % [shows])
	await _free(anchor)
	await _free(shield)


func _test_damage_number() -> void:
	print("[Damage numbers]")
	var n: Label3D = DamageNumber.new()
	n.set(&"auto_animate", false)
	root.add_child(n)
	n.call(&"configure", Vector3(0, 1, 0), 12.4)
	_check(n.text == "-12", "damage number text '%s'" % n.text)
	n.call(&"advance", 0.4)
	_check(n.position.y > 1.2 and n.modulate.a < 1.0, "number rises and fades")
	n.call(&"advance", 0.5)
	_check(n.is_queued_for_deletion(), "number frees itself")
	var blocked: Label3D = DamageNumber.new()
	blocked.call(&"configure", Vector3.ZERO, 0.0)
	_check(blocked.text == "Blocked", "zero damage shows Blocked")
	blocked.free()
	await process_frame


func _test_hud() -> void:
	print("[Combat HUD]")
	var hud := _spawn(HUD_SCENE)
	hud.set(&"auto_animate", false)
	await process_frame
	var panel: PanelContainer = hud.get(&"panel")
	_check(panel != null and is_equal_approx(panel.anchor_top, 1.0) and is_equal_approx(panel.anchor_left, 0.0), "HUD panel anchored bottom-left")
	hud.call(&"set_health", 80.0, 100.0)
	var health_bar: ProgressBar = hud.get(&"health_bar")
	_check(is_equal_approx(health_bar.value, 80.0) and (hud.get(&"health_label") as Label).text == "HP 80 / 100", "health row shows 80 / 100")
	hud.call(&"start_bolt_cooldown", 0.6)
	var bolt_label: Label = hud.get(&"bolt_label")
	_check(bolt_label.text == "Bolt: 0.6s" and not bool(hud.call(&"is_bolt_ready")), "bolt cooldown displayed")
	hud.call(&"advance", 0.7)
	_check(bolt_label.text == "Bolt: Ready", "bolt becomes ready after cooldown")
	var dash_label: Label = hud.get(&"dash_label")
	hud.call(&"set_dash_state", false, true)
	_check(dash_label.text == "Dash: Dashing", "dash row shows Dashing")
	hud.call(&"start_dash_cooldown", 0.5)
	_check(dash_label.text == "Dash: 0.5s", "dash cooldown displayed")
	hud.call(&"advance", 0.6)
	_check(dash_label.text == "Dash: Ready" and bool(hud.get(&"dash_ready")), "dash becomes ready")
	var shield_label: Label = hud.get(&"shield_label")
	hud.call(&"set_shield_state", true, 0.75)
	_check(shield_label.text == "Shield: 75%" and is_equal_approx((hud.get(&"shield_bar") as ProgressBar).value, 0.75), "shield row shows 75%")
	hud.call(&"set_shield_state", false, 0.0)
	_check(shield_label.text == "Shield: Broken", "broken shield state")
	hud.call(&"set_shield_state", false, 0.5)
	_check(shield_label.text == "Shield: Off", "inactive shield state")
	hud.call(&"set_bolt_cooldown", 0.25, 0.5)
	hud.call(&"advance", 1.0)
	_check(bolt_label.text == "Bolt: 0.2s" or bolt_label.text == "Bolt: 0.3s", "exact cooldowns are not ticked locally ('%s')" % bolt_label.text)
	await _free(hud)


func _test_adapter_preview() -> void:
	print("[Adapter: standalone preview]")
	var layer := _spawn(LAYER_SCENE)
	await _frames(3)
	var adapter := layer.get_node("CombatVisualAdapter")
	var effects := layer.get_node("Effects")
	_check(bool(adapter.call(&"is_preview_mode")) and adapter.get(&"controller") == null, "no gameplay -> preview mode, no errors")
	_check(adapter.get(&"hud") == layer.get_node("CombatHUD"), "adapter found the HUD")
	adapter.call(&"show_magic_bolt", Vector3(0, 1, 0), Vector3.FORWARD, 4.0)
	_check(_children_with_script(effects, MagicBolt).size() == 1, "preview bolt spawned under Effects")
	_check(not bool(layer.get_node("CombatHUD").call(&"is_bolt_ready")), "HUD estimates bolt cooldown")
	await _free(layer)


func _test_adapter_gameplay() -> void:
	print("[Adapter: gameplay signals]")
	var courier := Node3D.new()
	courier.name = "MockCourier"
	root.add_child(courier)
	var controller := _mock(CONTROLLER_SRC, "CombatController")
	var health := _mock(HEALTH_SRC, "CombatHealth")
	courier.add_child(controller)
	courier.add_child(health)
	var layer := (load(LAYER_SCENE) as PackedScene).instantiate()
	layer.get_node("CombatVisualAdapter").set(&"auto_discover", false)  # bind explicitly here
	root.add_child(layer)
	await process_frame
	var adapter := layer.get_node("CombatVisualAdapter")
	var hud := layer.get_node("CombatHUD")
	var effects := layer.get_node("Effects")
	var modes := []
	adapter.connect(&"binding_changed", func(p): modes.append(p))

	_check(bool(adapter.call(&"bind_controller", controller)), "bind_controller connects by signal name")
	_check(not bool(adapter.call(&"is_preview_mode")) and modes == [false], "binding leaves preview mode")
	_check(adapter.get(&"actor") == courier and adapter.get(&"player_health") == health, "actor and sibling CombatHealth discovered")

	health.emit_signal(&"health_changed", 60, 100)
	_check((hud.get(&"health_label") as Label).text == "HP 60 / 100", "health_changed -> HUD health")
	health.emit_signal(&"damaged", 15, Vector3.ZERO)
	await process_frame
	_check(_children_with_script(effects, DamageNumber).size() == 1, "player damaged -> floating number")

	controller.emit_signal(&"magic_bolt_fired", Vector3(0, 1, 0), Vector3(0, 0, -1))
	var bolts := _children_with_script(effects, MagicBolt)
	_check(bolts.size() == 1, "magic_bolt_fired -> bolt VFX")
	controller.set(&"bolt_remaining", 0.3)
	await process_frame
	_check((hud.get(&"bolt_label") as Label).text == "Bolt: 0.3s", "exact cooldown polled from controller ('%s')" % (hud.get(&"bolt_label") as Label).text)

	var slime := _spawn(SLIME_SCENE) as Node3D
	slime.set(&"auto_animate", false)
	slime.position = Vector3(0, 0, -3)
	var enemy_health := _mock(HEALTH_SRC, "EnemyHealth")
	slime.add_child(enemy_health)
	await process_frame
	_check(bool(adapter.call(&"bind_enemy", enemy_health, slime)), "bind_enemy links enemy health to visual")
	controller.emit_signal(&"target_hit", enemy_health, 10)
	_check(bool(bolts[0].get(&"has_impacted")), "target_hit ends the bolt at the target")
	_check(int(slime.get(&"state")) == S.IDLE, "health-bound enemy is not double-hit by target_hit")
	enemy_health.emit_signal(&"damaged", 10, Vector3(0, 1, 0))
	_check(int(slime.get(&"state")) == S.HIT, "enemy damaged -> hit animation")
	enemy_health.emit_signal(&"died")
	_check(int(slime.get(&"state")) == S.DEAD, "enemy died -> death animation")

	var target := Node3D.new()
	root.add_child(target)
	var wisp := (load(WISP_SCENE) as PackedScene).instantiate()
	wisp.set(&"auto_animate", false)
	target.add_child(wisp)
	await process_frame
	controller.emit_signal(&"target_hit", target, 5)
	_check(int(wisp.get(&"state")) == S.HIT, "target_hit finds an unbound child visual and plays hit")

	controller.emit_signal(&"dash_started")
	_check((hud.get(&"dash_label") as Label).text == "Dash: Dashing", "dash_started -> HUD Dashing")
	courier.global_position = Vector3(2, 0, 0)
	controller.emit_signal(&"dash_finished")
	var dashes := _children_with_script(effects, DashVfx)
	_check(dashes.size() == 1, "dash_finished -> afterimage trail")
	if dashes.size() == 1:
		var ghosts: Array = dashes[0].get(&"ghosts")
		_check(ghosts.size() > 0 and (ghosts[-1] as Node3D).position.x > 1.0, "trail spans from dash start to the courier")
	_check(not bool(hud.get(&"dash_ready")), "HUD shows dash cooldown after dash")

	controller.emit_signal(&"shield_changed", true, 0.8)
	var shield: Node3D = adapter.get(&"shield_vfx")
	_check(shield != null and bool(shield.call(&"is_shown")), "shield_changed -> package shield bubble")
	_check((hud.get(&"shield_label") as Label).text == "Shield: 80%", "shield_changed -> HUD shield")
	await process_frame
	_check(shield.global_position.is_equal_approx(courier.global_position + Vector3(0, 0.9, 0)), "shield follows the courier")

	adapter.call(&"unbind_player_health")
	adapter.call(&"unbind_controller")
	_check(bool(adapter.call(&"is_preview_mode")) and not controller.is_connected(&"magic_bolt_fired", Callable(adapter, "_on_magic_bolt_fired")), "unbinding restores preview mode")
	await _free(target)
	await _free(slime)
	await _free(layer)
	await _free(courier)


func _test_adapter_auto_discovery() -> void:
	print("[Adapter: auto discovery]")
	var scene := Node3D.new()
	scene.name = "IntegratedScene"
	root.add_child(scene)
	current_scene = scene
	var player := Node3D.new()
	player.name = "Player"
	scene.add_child(player)
	player.add_child(_mock(CONTROLLER_SRC, "CombatController"))
	player.add_child(_mock(HEALTH_SRC, "CombatHealth"))
	var layer := (load(LAYER_SCENE) as PackedScene).instantiate()
	scene.add_child(layer)
	await _frames(3)
	var adapter := layer.get_node("CombatVisualAdapter")
	_check(adapter.get(&"controller") == player.get_node("CombatController"), "adapter auto-discovers the CombatController")
	_check(adapter.get(&"player_health") == player.get_node("CombatHealth") and not bool(adapter.call(&"is_preview_mode")), "auto-discovery binds player health and leaves preview")
	current_scene = null
	await _free(scene)


func _test_showcase() -> void:
	print("[Forest encounter showcase]")
	var showcase := (load(SHOWCASE_SCENE) as PackedScene).instantiate() as Node3D
	showcase.set(&"auto_demo", false)
	root.add_child(showcase)
	current_scene = showcase
	await _frames(5)

	var enemies: Array = showcase.get(&"enemies")
	var slimes := 0
	var wisps := 0
	for e in enemies:
		var n := String((e as Node).name)
		slimes += 1 if n.begins_with("ForestSlime") else 0
		wisps += 1 if n.begins_with("FrostWisp") else 0
	_check(slimes == 2 and wisps == 2, "encounter has 2 slimes and 2 wisps")
	var camera: Camera3D = showcase.get(&"camera")
	_check(camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL and root.get_viewport().get_camera_3d() == camera, "isometric orthographic showcase camera is active")
	_check(showcase.get_node("Forest/Trees").get_child_count() == 22, "forest ring of 22 low-poly pines")
	_check(showcase.get_node_or_null("CourierStandIn/Body/Package") != null, "courier stand-in carries a package")
	var hud: Node = showcase.get(&"hud")
	_check(hud != null and (hud.get(&"health_label") as Label).text == "HP 100 / 100", "combat HUD shows full health")
	_check(bool(showcase.call(&"is_preview_mode")), "showcase boots in preview mode without gameplay")
	var help: Label = showcase.get(&"help_label")
	_check(help.text.contains("Preview") and help.text.contains("[1] Magic bolt"), "help overlay lists preview triggers")

	var effects: Node = showcase.get(&"effects_root")
	var target: Node3D = showcase.call(&"_nearest_living_enemy")
	_check(bool(showcase.call(&"trigger_preview", &"bolt")), "preview bolt fires")
	_check(_children_with_script(effects, MagicBolt).size() == 1, "bolt VFX spawned in the encounter")
	_check(not bool(showcase.call(&"trigger_preview", &"bolt")), "bolt respects preview cooldown")
	await _wait(0.7)
	_check(int(showcase.call(&"get_enemy_hp", target)) == 2, "bolt impact damages the nearest enemy (preview hp)")
	_check(_children_with_script(effects, DamageNumber).size() >= 1, "impact damage number spawned")
	for i in 2:
		showcase.call(&"trigger_preview", &"bolt")
		await _wait(0.7)
	var living: Array = showcase.call(&"get_living_enemies")
	_check(bool(target.call(&"is_dead")) and living.size() == 3, "three bolts defeat the enemy")
	showcase.call(&"_update_respawns", 3.0)
	_check(not bool(target.call(&"is_dead")) and target.visible, "defeated enemy respawns")

	var courier: Node3D = showcase.get(&"courier")
	var before := courier.global_position
	_check(bool(showcase.call(&"trigger_preview", &"dash")), "preview dash")
	_check(is_equal_approx(before.distance_to(courier.global_position), float(showcase.get(&"dash_distance"))), "courier moved by dash distance")
	_check(_children_with_script(effects, DashVfx).size() == 1, "dash afterimages spawned")
	_check(not bool(hud.get(&"dash_ready")), "HUD shows dash cooldown")

	showcase.call(&"trigger_preview", &"shield")
	var adapter: Node = showcase.get(&"adapter")
	var shield: Node3D = adapter.get(&"shield_vfx")
	_check(shield != null and bool(shield.call(&"is_shown")), "preview shield raised around the package")
	showcase.call(&"trigger_preview", &"hurt")
	_check(is_equal_approx(float(showcase.get(&"player_hp")), 100.0) and float(showcase.get(&"shield_durability")) < 1.0, "shield absorbs the hit")
	_check((hud.get(&"shield_label") as Label).text == "Shield: 66%", "HUD shield durability drops")
	showcase.call(&"trigger_preview", &"shield")
	showcase.call(&"trigger_preview", &"hurt")
	_check(is_equal_approx(float(showcase.get(&"player_hp")), 85.0) and (hud.get(&"health_label") as Label).text == "HP 85 / 100", "unshielded hit lowers HUD health")

	showcase.call(&"trigger_preview", &"move")
	var e0: Node3D = enemies[0]
	var p0 := e0.position
	await _wait(0.3)
	_check(int(e0.get(&"state")) == S.MOVE and not e0.position.is_equal_approx(p0), "enemies switch to move animation and wander")

	_check(bool(showcase.call(&"trigger_preview", &"reset")), "preview reset")
	var all_idle := true
	for e in enemies:
		all_idle = all_idle and int((e as Node).get(&"state")) == S.IDLE
	_check(all_idle and is_equal_approx(float(showcase.get(&"player_hp")), 100.0), "reset restores enemies and health")

	var controller := _mock(CONTROLLER_SRC, "CombatController")
	showcase.add_child(controller)
	adapter.call(&"bind_controller", controller)
	_check(not bool(showcase.call(&"is_preview_mode")) and not bool(showcase.call(&"trigger_preview", &"bolt")), "gameplay link disables preview triggers")
	_check(help.text.contains("Gameplay linked"), "help overlay reports gameplay link")
	current_scene = null
	await _free(showcase)


func _test_showcase_auto_demo() -> void:
	print("[Showcase auto demo]")
	var showcase := (load(SHOWCASE_SCENE) as PackedScene).instantiate() as Node3D
	showcase.set(&"demo_interval", 0.05)
	root.add_child(showcase)
	current_scene = showcase
	await _wait(0.6)
	_check(int(showcase.get(&"_demo_step")) >= 3 and String(showcase.get(&"last_action")) != "", "auto demo cycles preview actions (step %d)" % int(showcase.get(&"_demo_step")))
	current_scene = null
	await _free(showcase)
