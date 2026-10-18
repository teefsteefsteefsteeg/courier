extends SceneTree
## Phase 4 gameplay checks (combat): CombatHealth, projectiles, Magic Bolt, Dash, Package
## Shield, Forest Slime, Frost Wisp, courier integration, the combat sandbox, and
## regressions (input bindings, player scene wiring, village scene).
##   godot --headless --path . --script res://tests/phase4_gameplay_tests.gd
## Exit code = number of failed checks. Run tests/phase2_tests.gd and tests/phase3_tests.gd
## for earlier-phase regression.
## Abilities and enemy AI are stepped synchronously with a fixed STEP, so their results are
## deterministic; only projectile flight waits on real physics frames.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SLIME_SCENE := "res://scenes/gameplay/combat/forest_slime.tscn"
const WISP_SCENE := "res://scenes/gameplay/combat/frost_wisp.tscn"
const SANDBOX := "res://scenes/gameplay/combat/combat_sandbox.tscn"
const VILLAGE := "res://scenes/levels/village.tscn"
const PARCEL := "res://data/packages/pkg_ordinary_parcel.tres"
const STEP := 1.0 / 60.0
const ES := Enemy.State

var _failures: int = 0
var _passes: int = 0
var arena: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_input_actions()
	_test_health()
	_test_controller_without_body()
	await _test_projectile()
	await _test_player_wiring()
	await _test_magic_bolt_cooldown()
	await _test_magic_bolt_damage()
	await _test_dash()
	await _test_shield()
	await _test_slime()
	await _test_wisp()
	await _test_integration()
	await _test_determinism()
	await _test_sandbox()
	_test_regressions()

	print("\n=== Phase 4 gameplay tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -------------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _physics_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _new_arena() -> Node3D:
	arena = Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	current_scene = arena
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	arena.add_child(floor_body)
	return arena


func _free_arena() -> void:
	if arena != null:
		arena.queue_free()
		arena = null
	await process_frame
	await physics_frame


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Wall"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	arena.add_child(body)
	body.global_position = pos
	return body


## Minimal stand-in target: a body on the player layer with a capsule and a CombatHealth.
func _dummy(pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Dummy"
	body.collision_layer = CombatController.PLAYER_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(shape)
	var health := CombatHealth.new()
	health.name = "Health"
	body.add_child(health)
	arena.add_child(body)
	body.global_position = pos
	return body


func _spawn_player(pos: Vector3) -> PlayerController:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerController
	arena.add_child(player)
	player.teleport_to(pos)
	CombatController.find_on(player).simulate = false
	return player


func _spawn_enemy(path: String, pos: Vector3) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.simulate = false
	arena.add_child(enemy)
	enemy.global_position = pos
	return enemy


func _step(enemy: Enemy, count: int) -> void:
	for i in count:
		enemy.advance(STEP)


func _step_until(enemy: Enemy, state: Enemy.State, max_steps: int = 600) -> void:
	var steps := 0
	while enemy.state != state and steps < max_steps:
		enemy.advance(STEP)
		steps += 1


func _projectiles() -> Array[CombatProjectile]:
	var result: Array[CombatProjectile] = []
	if arena != null:
		for child in arena.get_children():
			if child is CombatProjectile and not child.is_queued_for_deletion():
				result.append(child)
	return result


func _has_physical_key(action: StringName, key: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and int((event as InputEventKey).physical_keycode) == key:
			return true
	return false


func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	return event


## Last recorded event, or [] when nothing was recorded (safe to compare with ==).
func _last(events: Array) -> Variant:
	return events.back() if not events.is_empty() else []


# --- input & components ----------------------------------------------------------

func _test_input_actions() -> void:
	print("[Input actions]")
	for action in [&"combat_magic_bolt", &"combat_dash", &"package_shield"]:
		_check(InputMap.has_action(action), "action %s exists" % action)
	_check(_has_physical_key(&"combat_magic_bolt", KEY_SPACE), "Magic Bolt bound to Space")
	_check(_has_physical_key(&"combat_dash", KEY_SHIFT), "Dash bound to Shift")
	_check(_has_physical_key(&"package_shield", KEY_Q), "Package Shield bound to Q")
	_check(InputMap.event_is_action(_key_event(KEY_SPACE), &"combat_magic_bolt"), "Space event triggers combat_magic_bolt")
	_check(InputMap.event_is_action(_key_event(KEY_Q), &"package_shield") and not InputMap.event_is_action(_key_event(KEY_Q), &"interact"), "Q triggers package_shield only")
	var existing := {
		&"move_forward": KEY_W, &"move_back": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
		&"run": KEY_SHIFT, &"interact": KEY_E, &"toggle_journal": KEY_J, &"drop_package": KEY_G,
		&"toggle_debug_hud": KEY_F3,
	}
	for action in existing:
		_check(_has_physical_key(action, existing[action]), "existing binding %s unchanged" % action)
	_check(InputMap.has_action(&"zoom_in") and InputMap.has_action(&"zoom_out"), "zoom actions still present")


func _test_health() -> void:
	print("[CombatHealth]")
	var h := CombatHealth.new()
	h.max_health = 50.0
	root.add_child(h)
	var changed := []
	var damaged := []
	var blocked := []
	var died := [0]
	h.health_changed.connect(func(c, m): changed.append([c, m]))
	h.damaged.connect(func(a, p): damaged.append([a, p]))
	h.damage_blocked.connect(func(a, _p): blocked.append(a))
	h.died.connect(func(): died[0] += 1)
	_check(is_equal_approx(h.get_health(), 50.0) and not h.is_dead() and is_equal_approx(h.get_health_ratio(), 1.0), "starts at max health")
	var source := Vector3(1.0, 2.0, 3.0)
	_check(h.apply_damage(10.0, source), "apply_damage returns true when health drops")
	_check(is_equal_approx(h.get_health(), 40.0), "10 damage -> 40")
	_check(changed == [[40.0, 50.0]], "health_changed(current, max) = %s" % [changed])
	_check(damaged.size() == 1 and is_equal_approx(damaged[0][0], 10.0) and damaged[0][1] == source, "damaged(amount, source_position)")
	_check(not h.apply_damage(0.0) and not h.apply_damage(-5.0) and changed.size() == 1, "zero/negative damage ignored silently")
	h.invulnerable = true
	_check(not h.apply_damage(15.0) and is_equal_approx(h.get_health(), 40.0) and blocked == [15.0], "invulnerable blocks and emits damage_blocked")
	h.invulnerable = false
	h.damage_interceptor = func(amount: float, _p: Vector3) -> float: return amount * 0.5
	_check(h.apply_damage(10.0) and is_equal_approx(h.get_health(), 35.0) and is_equal_approx(h.last_damage_taken, 5.0), "interceptor halves damage")
	h.damage_interceptor = func(amount: float, _p: Vector3) -> float: return amount * 3.0
	h.apply_damage(5.0)
	_check(is_equal_approx(h.get_health(), 30.0), "interceptor cannot amplify damage")
	h.damage_interceptor = func(_a: float, _p: Vector3) -> float: return 0.0
	_check(not h.apply_damage(10.0) and is_equal_approx(h.get_health(), 30.0) and blocked.size() == 2, "fully intercepted damage returns false")
	h.damage_interceptor = Callable()
	_check(is_equal_approx(h.heal(100.0), 20.0) and is_equal_approx(h.get_health(), 50.0), "heal clamps to max")
	_check(h.apply_damage(80.0) and h.is_dead() and is_equal_approx(h.get_health(), 0.0), "overkill clamps to 0 and kills")
	_check(died[0] == 1, "died emitted once")
	_check(not h.apply_damage(5.0) and is_equal_approx(h.heal(10.0), 0.0) and died[0] == 1, "dead: no damage, no heal, no second died")
	h.reset()
	_check(not h.is_dead() and is_equal_approx(h.get_health(), 50.0), "reset revives at full health")
	h.apply_damage(50.0)
	_check(died[0] == 2, "died re-armed after reset")
	var holder := Node.new()
	var middle := Node.new()
	var deep := CombatHealth.new()
	holder.add_child(middle)
	middle.add_child(deep)
	_check(CombatHealth.find_on(holder) == deep and CombatHealth.find_on(deep) == deep and CombatHealth.find_on(null) == null, "find_on searches self, children and grandchildren")
	holder.free()
	h.queue_free()


func _test_controller_without_body() -> void:
	print("[CombatController without a body]")
	var combat := CombatController.new()
	root.add_child(combat)
	var blocked := []
	combat.ability_blocked.connect(func(a, r): blocked.append([a, r]))
	_check(not combat.try_magic_bolt() and _last(blocked) == [&"magic_bolt", &"no_body"], "bolt refused without a body")
	_check(not combat.try_dash() and _last(blocked) == [&"dash", &"no_body"], "dash refused without a body")
	_check(not combat.set_package_shield_enabled(true) and _last(blocked) == [&"package_shield", &"no_package"], "shield refused without a carrier")
	combat.queue_free()


func _test_projectile() -> void:
	print("[CombatProjectile]")
	_new_arena()
	var p := CombatProjectile.new()
	p.simulate = false
	p.speed = 10.0
	p.max_distance = 6.0
	p.direction = Vector3.RIGHT
	arena.add_child(p)
	p.global_position = Vector3(0.0, 5.0, 0.0)
	var reasons := []
	p.expired.connect(func(r): reasons.append(r))
	_check(p.get_node_or_null(^"PlaceholderVisual") != null, "placeholder visual built when the scene has none")
	p.advance(0.5)
	_check(is_equal_approx(p.traveled, 5.0) and p.global_position.is_equal_approx(Vector3(5.0, 5.0, 0.0)) and reasons.is_empty(), "moves speed * delta")
	p.advance(0.5)
	_check(is_equal_approx(p.traveled, 6.0) and reasons == [CombatProjectile.REASON_RANGE] and p.is_finished(), "stops at max_distance and expires (range)")
	p.advance(0.5)
	_check(reasons.size() == 1 and is_equal_approx(p.traveled, 6.0), "finished projectile is inert")

	var wall := _wall(Vector3(3.0, 1.0, 0.0), Vector3(0.5, 2.0, 4.0))
	var dummy := _dummy(Vector3(6.0, 0.0, 0.0))
	await _physics_frames(2)
	var q := CombatProjectile.new()
	q.simulate = false
	q.speed = 60.0
	q.max_distance = 20.0
	q.direction = Vector3.RIGHT
	q.collision_mask = 3
	arena.add_child(q)
	q.global_position = Vector3(0.0, 0.8, 0.0)
	var q_reasons := []
	q.expired.connect(func(r): q_reasons.append(r))
	q.advance(1.0)
	_check(q_reasons == [CombatProjectile.REASON_BLOCKED] and q.global_position.x < 3.0 and is_equal_approx(CombatHealth.find_on(dummy).get_health(), 100.0), "fast projectile stopped by a thin wall (no tunnelling)")
	wall.queue_free()
	await _physics_frames(2)
	var r := CombatProjectile.new()
	r.simulate = false
	r.speed = 60.0
	r.max_distance = 20.0
	r.direction = Vector3.RIGHT
	r.collision_mask = 3
	r.damage = 7.0
	arena.add_child(r)
	r.global_position = Vector3(0.0, 0.8, 0.0)
	var hits := []
	r.hit.connect(func(t, a): hits.append([t, a]))
	r.advance(1.0)
	_check(hits.size() == 1 and hits[0][0] == dummy and is_equal_approx(hits[0][1], 7.0), "hit(target, amount) on the first damageable body")
	var s := CombatProjectile.new()
	s.simulate = false
	s.speed = 60.0
	s.direction = Vector3.LEFT
	s.collision_mask = 3
	s.source = dummy
	arena.add_child(s)
	s.global_position = dummy.global_position + Vector3(0.0, 0.8, 0.0)
	s.advance(0.1)
	_check(is_equal_approx(CombatHealth.find_on(dummy).get_health(), 93.0), "projectile never hits its source")
	await _free_arena()


func _test_player_wiring() -> void:
	print("[Player wiring]")
	_new_arena()
	var player := _spawn_player(Vector3.ZERO)
	await _physics_frames(3)
	var combat := CombatController.find_on(player)
	_check(combat != null and combat.name == &"Combat", "player has a Combat child")
	_check(combat.health != null and combat.health == player.get_node(^"Combat/Health") and CombatHealth.find_on(player) == combat.health, "Combat/Health resolves via find_on")
	_check(combat.health.damage_interceptor.is_valid(), "controller installed its damage interceptor")
	_check(player.is_in_group(CombatController.PLAYER_GROUP), "player registered as enemy target")
	_check(combat.get_carrier() != null and combat.get_carrier() == PackageCarrier.find_on(player), "combat sees the PackageCarrier")
	_check(player.movement != null and player.facing != null and player.interaction != null, "Phase 1 components still wired")
	_check(is_equal_approx(combat.get_shield_durability(), combat.shield_max_durability) and not combat.is_shield_active(), "shield starts full and lowered")
	_check(combat.is_magic_bolt_ready() and not combat.is_dashing() and is_equal_approx(combat.get_dash_cooldown_remaining(), 0.0), "abilities start ready")
	_check(combat.get_aim_direction().is_equal_approx(Vector3.FORWARD), "aim defaults to the courier's facing (-Z)")
	await _free_arena()


# --- Magic Bolt ----------------------------------------------------------------

func _test_magic_bolt_cooldown() -> void:
	print("[Magic Bolt: cooldown]")
	_new_arena()
	var player := _spawn_player(Vector3.ZERO)
	var combat := CombatController.find_on(player)
	await _physics_frames(2)
	var fired := []
	var blocked := []
	combat.magic_bolt_fired.connect(func(o, d): fired.append([o, d]))
	combat.ability_blocked.connect(func(a, r): blocked.append([a, r]))
	_check(combat.try_magic_bolt(), "first bolt fires")
	var origin: Vector3 = fired[0][0] if fired.size() > 0 else Vector3.INF
	var direction: Vector3 = fired[0][1] if fired.size() > 0 else Vector3.ZERO
	_check(direction.is_equal_approx(Vector3.FORWARD), "magic_bolt_fired direction = facing (got %s)" % direction)
	var expected_origin := player.global_position + Vector3.UP * combat.bolt_spawn_height + Vector3.FORWARD * combat.bolt_spawn_forward
	_check(origin.is_equal_approx(expected_origin), "magic_bolt_fired origin at hand height (got %s)" % origin)
	var bolts := _projectiles()
	_check(bolts.size() == 1 and is_equal_approx(bolts[0].damage, combat.bolt_damage) and bolts[0].source == player, "one bolt spawned with controller damage and the courier as source")
	_check(not combat.try_magic_bolt() and _last(blocked) == [&"magic_bolt", &"cooldown"], "second bolt blocked by cooldown")
	combat.advance(0.4)
	_check(not combat.try_magic_bolt() and combat.get_magic_bolt_cooldown_remaining() > 0.0, "still cooling down at 0.4 s (cooldown 0.45 s)")
	combat.advance(0.06)
	_check(combat.is_magic_bolt_ready() and combat.try_magic_bolt(Vector3(1.0, 5.0, 0.0)), "fires once the cooldown elapsed")
	var second: Vector3 = fired[1][1] if fired.size() > 1 else Vector3.ZERO
	_check(fired.size() == 2 and second.is_equal_approx(Vector3.RIGHT), "explicit direction flattened and normalized")
	_check(_projectiles().size() == 2, "exactly two bolts were spawned")
	await _free_arena()


func _test_magic_bolt_damage() -> void:
	print("[Magic Bolt: damage]")
	_new_arena()
	var player := _spawn_player(Vector3.ZERO)
	var combat := CombatController.find_on(player)
	var slime := _spawn_enemy(SLIME_SCENE, Vector3(0.0, 0.0, -5.0)) as ForestSlime
	slime.free_on_death = false
	await _physics_frames(3)
	var hits := []
	combat.target_hit.connect(func(t, a): hits.append([t, a]))
	var defeated := [0]
	slime.defeated.connect(func(_e): defeated[0] += 1)
	combat.try_magic_bolt(Vector3.FORWARD)
	await _physics_frames(30)
	_check(hits.size() == 1 and hits[0][0] == slime and is_equal_approx(hits[0][1], 20.0), "bolt hits the slime: target_hit(slime, 20)")
	_check(is_equal_approx(slime.health.get_health(), 20.0), "slime at 20 / 40")
	_check(slime.provoked, "damage provokes the slime")
	combat.advance(1.0)
	combat.try_magic_bolt(Vector3.FORWARD)
	await _physics_frames(30)
	_check(slime.health.is_dead() and slime.is_dead() and defeated[0] == 1, "second bolt kills the slime; defeated emitted once")
	_check(slime.collision_layer == 0 and slime.collision_mask == 0, "defeated slime stops colliding")
	var before := hits.size()
	combat.advance(1.0)
	combat.try_magic_bolt(Vector3.FORWARD)
	await _physics_frames(20)
	_check(hits.size() == before, "bolts pass through a defeated enemy")
	var dead_position := slime.global_position
	_step(slime, 10)
	_check(slime.state == ES.DEAD and slime.global_position == dead_position, "defeated enemies ignore advance()")

	var target := _spawn_enemy(SLIME_SCENE, Vector3(3.0, 0.0, -6.0))
	_wall(Vector3(2.0, 1.0, -3.0), Vector3(6.0, 2.0, 0.5))
	await _physics_frames(3)
	combat.advance(1.0)
	combat.try_magic_bolt(Vector3(3.0, 0.0, -6.0))
	var blocked_bolt: CombatProjectile = _projectiles().back()
	var reasons := []
	blocked_bolt.expired.connect(func(r): reasons.append(r))
	await _physics_frames(20)
	_check(reasons == [CombatProjectile.REASON_BLOCKED] and is_equal_approx(target.health.get_health(), 40.0), "walls block bolts")

	combat.advance(1.0)
	combat.bolt_spawn_forward = 0.0
	combat.bolt_range = 3.0
	var hp := combat.health.get_health()
	combat.try_magic_bolt(Vector3.BACK)
	var own_bolt: CombatProjectile = _projectiles().back()
	var own_reasons := []
	own_bolt.expired.connect(func(r): own_reasons.append(r))
	await _physics_frames(15)
	_check(is_equal_approx(combat.health.get_health(), hp) and own_reasons == [CombatProjectile.REASON_RANGE], "a bolt spawned inside the courier never hurts them and expires at bolt_range")
	await _free_arena()


# --- Dash ------------------------------------------------------------------------

func _test_dash() -> void:
	print("[Dash]")
	_new_arena()
	var player := _spawn_player(Vector3.ZERO)
	var combat := CombatController.find_on(player)
	_wall(Vector3(-2.0, 1.0, 0.0), Vector3(0.5, 2.0, 4.0))
	await _physics_frames(5)
	var events := []
	var blocked := []
	combat.dash_started.connect(func(): events.append("start"))
	combat.dash_finished.connect(func(): events.append("finish"))
	combat.ability_blocked.connect(func(a, r): blocked.append([a, r]))
	var start := player.global_position
	_check(combat.try_dash(Vector3.RIGHT) and combat.is_dashing() and events == ["start"], "dash starts (dash_started)")
	_check(not combat.try_dash() and _last(blocked) == [&"dash", &"dashing"], "cannot dash while dashing")
	_check(not combat.health.apply_damage(30.0) and is_equal_approx(combat.health.get_health(), 100.0), "dash grants invulnerability")
	for i in 20:
		combat.advance(STEP)
	_check(events == ["start", "finish"] and not combat.is_dashing(), "dash_finished once after dash_duration")
	var moved := player.global_position - start
	_check(absf(moved.x - combat.dash_speed * combat.dash_duration) < 0.05 and absf(moved.z) < 0.01, "dash covers dash_speed * dash_duration = 3.2 m (got %.3f)" % moved.x)
	_check(combat.health.apply_damage(10.0) and is_equal_approx(combat.health.get_health(), 90.0), "damage applies again after the dash")
	_check(not combat.try_dash(Vector3.RIGHT) and _last(blocked) == [&"dash", &"cooldown"], "dash on cooldown afterwards")
	combat.advance(0.6)
	_check(is_equal_approx(combat.get_dash_cooldown_remaining(), 0.0) and combat.try_dash(Vector3.LEFT), "dash available after dash_cooldown (counted from dash start)")
	for i in 20:
		combat.advance(STEP)
	_check(absf(player.global_position.x - start.x) < 0.05, "dashing back returns to the start")
	combat.advance(1.0)
	combat.try_dash(Vector3.LEFT)
	for i in 20:
		combat.advance(STEP)
	var x := player.global_position.x
	_check(x > -1.45 and x < -1.2 and absf(player.global_position.z - start.z) < 0.01, "dash stops at walls (x = %.3f)" % x)
	combat.advance(1.0)
	_check(combat.try_dash() and combat.get_dash_direction().is_equal_approx(Vector3.FORWARD), "dash without input goes along the facing")
	for i in 20:
		combat.advance(STEP)
	await _free_arena()


# --- Package Shield --------------------------------------------------------------

func _test_shield() -> void:
	print("[Package Shield]")
	_new_arena()
	var player := _spawn_player(Vector3.ZERO)
	var combat := CombatController.find_on(player)
	var carrier := PackageCarrier.find_on(player)
	carrier.simulate_mechanics = false
	var health := combat.health
	await _physics_frames(3)
	var shield_events := []
	var blocked := []
	var broken := [0]
	combat.shield_changed.connect(func(a, d): shield_events.append([a, d]))
	combat.ability_blocked.connect(func(a, r): blocked.append([a, r]))
	combat.shield_broken.connect(func(): broken[0] += 1)

	_check(not combat.set_package_shield_enabled(true) and not combat.is_shield_active() and _last(blocked) == [&"package_shield", &"no_package"], "shield refuses to rise without a package")
	_check(not combat.toggle_package_shield() and not combat.is_shield_active(), "toggle without a package also refused")
	_check(combat.set_package_shield_enabled(false) and shield_events.is_empty(), "lowering an inactive shield succeeds silently")
	var hp := health.get_health()
	health.apply_damage(10.0)
	_check(is_equal_approx(health.get_health(), hp - 10.0), "no package: damage goes straight to health")

	var parcel := PackageInstance.new(load(PARCEL))
	carrier.pick_up(parcel)
	_check(combat.is_carrying_package() and combat.set_package_shield_enabled(true) and combat.is_shield_active(), "shield rises while carrying")
	_check(_last(shield_events) == [true, 60.0], "shield_changed(true, 60)")
	hp = health.get_health()
	_check(not health.apply_damage(25.0, Vector3(1.0, 0.0, 0.0)), "fully absorbed hit: apply_damage returns false")
	_check(is_equal_approx(health.get_health(), hp) and is_equal_approx(combat.get_shield_durability(), 35.0), "shield absorbs 25: health unchanged, durability 35")
	_check(is_equal_approx(parcel.integrity, 100.0), "absorbed damage does not touch the package")
	_check(_last(shield_events) == [true, 35.0], "shield_changed(true, 35)")
	_check(health.apply_damage(50.0), "overflowing hit reaches health")
	_check(is_equal_approx(health.get_health(), hp - 15.0), "shield absorbs 35 of 50; 15 reaches health")
	_check(not combat.is_shield_active() and is_equal_approx(combat.get_shield_durability(), 0.0) and broken[0] == 1, "shield breaks at 0 durability (shield_broken)")
	_check(_last(shield_events) == [false, 0.0], "shield_changed(false, 0) on break")
	_check(is_equal_approx(parcel.integrity, 100.0 - 15.0 * combat.package_impact_per_damage), "overflow damage impacts the package (got %.2f)" % parcel.integrity)

	_check(not combat.set_package_shield_enabled(true) and _last(blocked) == [&"package_shield", &"shield_depleted"], "broken shield cannot rise until recharged")
	combat.advance(combat.shield_regen_delay)
	_check(is_equal_approx(combat.get_shield_durability(), 0.0), "no regeneration during shield_regen_delay")
	combat.advance(1.0)
	_check(is_equal_approx(combat.get_shield_durability(), 8.0), "regenerates 8 / s after the delay")
	_check(not combat.set_package_shield_enabled(true), "8 durability is below the activation threshold (15)")
	combat.advance(1.0)
	_check(combat.set_package_shield_enabled(true) and is_equal_approx(combat.get_shield_durability(), 16.0), "shield rises again at 16 durability")
	combat.advance(5.0)
	_check(is_equal_approx(combat.get_shield_durability(), 16.0), "no regeneration while raised")

	_check(combat.toggle_package_shield() and not combat.is_shield_active() and _last(shield_events)[0] == false, "toggle lowers the shield")
	var integrity := parcel.integrity
	hp = health.get_health()
	health.apply_damage(20.0)
	_check(is_equal_approx(health.get_health(), hp - 20.0) and is_equal_approx(parcel.integrity, integrity - 20.0 * combat.package_impact_per_damage), "unshielded hit while carrying: full damage and package impact")

	combat.advance(combat.shield_regen_delay)
	combat.advance(10.0)
	_check(is_equal_approx(combat.get_shield_durability(), combat.shield_max_durability), "regenerates up to max durability")
	combat.set_package_shield_enabled(true)
	hp = health.get_health()
	combat.try_dash(Vector3.BACK)
	health.apply_damage(30.0)
	_check(is_equal_approx(combat.get_shield_durability(), 60.0) and is_equal_approx(health.get_health(), hp), "dash invulnerability takes precedence over the shield")
	for i in 20:
		combat.advance(STEP)

	carrier.drop_package()
	_check(not combat.is_shield_active() and _last(shield_events)[0] == false, "dropping the package lowers the shield")
	hp = health.get_health()
	health.apply_damage(10.0)
	_check(is_equal_approx(health.get_health(), hp - 10.0) and is_equal_approx(combat.get_shield_durability(), 60.0), "without a package nothing is absorbed")
	_check(not combat.set_package_shield_enabled(true), "cannot raise the shield after dropping the package")

	carrier.pick_up(PackageInstance.new(load(PARCEL)))
	combat.set_package_shield_enabled(true)
	carrier.remove_package(&"delivered")
	_check(not combat.is_shield_active(), "delivering / removing the package lowers the shield")
	await _free_arena()


# --- Enemies ---------------------------------------------------------------------

func _test_slime() -> void:
	print("[Forest Slime]")
	_new_arena()
	var dummy := _dummy(Vector3.ZERO)
	var dummy_health := CombatHealth.find_on(dummy)
	var slime := _spawn_enemy(SLIME_SCENE, Vector3(10.0, 0.0, 0.0)) as ForestSlime
	slime.target = dummy
	slime.free_on_death = false
	await _physics_frames(3)
	_check(slime.collision_layer == CombatController.ENEMY_LAYER and slime.collision_mask == CombatController.WORLD_LAYER, "slime on the enemy layer, colliding with the world only")
	_check(slime.health != null and is_equal_approx(slime.health.max_health, 40.0), "slime has 40 HP")
	var attacks := []
	slime.attacked.connect(func(t, landed): attacks.append([t, landed]))
	var start := slime.global_position
	_step(slime, 30)
	_check(slime.state == ES.IDLE and Vector2(slime.global_position.x - start.x, slime.global_position.z - start.z).length() < 0.05, "idle and still while the target is beyond detection (10 m > 8 m)")
	dummy.global_position = Vector3(5.0, 0.0, 0.0)
	_step(slime, 1)
	_check(slime.state == ES.CHASE, "spots a target within detection_radius")
	var d0 := slime.horizontal_distance_to(dummy)
	_step(slime, 30)
	var closed := d0 - slime.horizontal_distance_to(dummy)
	_check(absf(closed - slime.move_speed * 0.5) < 0.1, "chases at move_speed (closed %.2f m in 0.5 s)" % closed)
	_step_until(slime, ES.WINDUP)
	_check(slime.state == ES.WINDUP and slime.horizontal_distance_to(dummy) <= slime.attack_range + 0.01, "winds up once within attack_range")
	var hp := dummy_health.get_health()
	_step(slime, 10)
	_check(slime.state == ES.WINDUP and is_equal_approx(dummy_health.get_health(), hp) and attacks.is_empty(), "no damage during the windup tell")
	_step(slime, 15)
	_check(slime.state == ES.RECOVER and is_equal_approx(dummy_health.get_health(), hp - slime.contact_damage), "strike lands for contact_damage after the windup")
	_check(_last(attacks) == [dummy, true], "attacked(target, true)")
	_step(slime, 30)
	_check(slime.state == ES.RECOVER and is_equal_approx(dummy_health.get_health(), hp - slime.contact_damage), "recovers (no attacks) during attack_cooldown")
	_step_until(slime, ES.WINDUP)
	_check(slime.state == ES.WINDUP, "attacks again after the cooldown")
	dummy.global_position = Vector3(1.0, 0.0, 0.0)
	_step(slime, 25)
	_check(_last(attacks) == [dummy, false] and is_equal_approx(dummy_health.get_health(), hp - slime.contact_damage) and slime.state == ES.RECOVER, "stepping out of reach during the windup dodges the strike")
	_step_until(slime, ES.CHASE)
	dummy.global_position = Vector3(-20.0, 0.0, 0.0)
	_step(slime, 1)
	_check(slime.state == ES.IDLE, "unprovoked slime loses interest beyond lose_interest_radius")
	slime.health.apply_damage(5.0, dummy.global_position)
	_step(slime, 1)
	_check(slime.provoked and slime.state == ES.CHASE, "provoked slime chases from any distance")
	dummy_health.apply_damage(1000.0)
	_step(slime, 1)
	_check(slime.state == ES.IDLE, "slime stops chasing a dead target")

	var defeated := []
	slime.defeated.connect(func(e): defeated.append(e))
	slime.health.apply_damage(100.0)
	_check(slime.is_dead() and defeated == [slime] and slime.collision_layer == 0, "slime dies: DEAD, defeated(self), collision off")
	slime.health.apply_damage(10.0)
	_check(defeated.size() == 1, "defeated emitted only once")
	_check(not slime.is_queued_for_deletion(), "free_on_death = false keeps the body")
	var doomed := _spawn_enemy(SLIME_SCENE, Vector3(0.0, 0.0, 10.0))
	doomed.death_free_delay = 0.0
	doomed.health.apply_damage(100.0)
	_check(doomed.is_queued_for_deletion(), "free_on_death frees the defeated body")
	await _free_arena()


func _test_wisp() -> void:
	print("[Frost Wisp]")
	_new_arena()
	var dummy := _dummy(Vector3.ZERO)
	var dummy_health := CombatHealth.find_on(dummy)
	var wisp := _spawn_enemy(WISP_SCENE, Vector3(0.0, 0.0, -14.0)) as FrostWisp
	wisp.target = dummy
	wisp.free_on_death = false
	await _physics_frames(3)
	_check(not wisp.use_gravity and is_equal_approx(wisp.health.max_health, 30.0) and wisp.collision_layer == CombatController.ENEMY_LAYER, "wisp hovers, has 30 HP, enemy layer")
	var telegraphs := []
	var shots := []
	wisp.attack_telegraphed.connect(func(p): telegraphs.append(p))
	wisp.shard_fired.connect(func(o, d): shots.append([o, d]))
	var y0 := wisp.global_position.y
	_step(wisp, 30)
	_check(wisp.state == ES.IDLE and shots.is_empty(), "idle beyond detection (14 m > 11 m)")
	wisp.global_position = Vector3(0.0, 0.0, -7.0)
	_step(wisp, 2)
	_check(wisp.state == ES.WINDUP and telegraphs.size() == 1, "in attack range: winds up and telegraphs")
	var aim: Vector3 = _last(telegraphs) if not telegraphs.is_empty() else Vector3.INF
	_check(aim.is_equal_approx(dummy.global_position + Vector3.UP * wisp.aim_height), "telegraph aims at the target's torso")
	_step(wisp, 30)
	_check(shots.is_empty() and wisp.state == ES.WINDUP, "no shard before attack_windup ends")
	_step(wisp, 10)
	_check(shots.size() == 1 and wisp.state == ES.CHASE and wisp.get_attack_cooldown_remaining() > 2.0, "fires one shard after the windup, cooldown started")
	_check(absf(wisp.global_position.y - y0) < 0.001, "wisp keeps its hover height")
	await _physics_frames(60)
	_check(is_equal_approx(dummy_health.get_health(), 100.0 - wisp.shard_damage), "frost shard hits the target for 12 (got %.1f)" % dummy_health.get_health())

	_step_until(wisp, ES.WINDUP)
	_check(wisp.state == ES.WINDUP and telegraphs.size() == 2, "winds up again after attack_cooldown")
	var preferred := wisp.horizontal_distance_to(dummy)
	_check(preferred <= wisp.preferred_distance + 0.55 and preferred >= wisp.preferred_distance - 0.55, "closed in to about preferred_distance (%.2f m)" % preferred)
	dummy.global_position = Vector3(3.0, 0.0, 0.0)
	_step(wisp, 40)
	await _physics_frames(80)
	_check(shots.size() == 2 and is_equal_approx(dummy_health.get_health(), 100.0 - wisp.shard_damage), "sidestepping during the windup dodges the locked-on shard")

	dummy.global_position = wisp.global_position + Vector3(2.0, 0.0, 0.0)
	_step(wisp, 1)
	_check(wisp.state == ES.RETREAT, "crowded wisp retreats (2 m < retreat_distance)")
	_step_until(wisp, ES.CHASE)
	_check(wisp.state == ES.CHASE and wisp.horizontal_distance_to(dummy) >= wisp.preferred_distance - 0.05, "retreats back to preferred_distance")

	wisp.global_position = Vector3(0.0, 0.0, -7.0)
	dummy.global_position = Vector3.ZERO
	var bystander := _spawn_enemy(SLIME_SCENE, Vector3(0.0, 0.0, -3.5))
	await _physics_frames(3)
	var hp := dummy_health.get_health()
	wisp.fire_shard(dummy.global_position + Vector3.UP * wisp.aim_height)
	await _physics_frames(60)
	_check(is_equal_approx(bystander.health.get_health(), 40.0) and is_equal_approx(dummy_health.get_health(), hp - wisp.shard_damage), "shards pass through other enemies")
	_wall(Vector3(0.0, 1.0, -2.0), Vector3(4.0, 2.0, 0.5))
	await _physics_frames(3)
	var shard := wisp.fire_shard(dummy.global_position + Vector3.UP * wisp.aim_height)
	var reasons := []
	shard.expired.connect(func(r): reasons.append(r))
	await _physics_frames(60)
	_check(reasons == [CombatProjectile.REASON_BLOCKED] and is_equal_approx(dummy_health.get_health(), hp - wisp.shard_damage), "walls block frost shards")

	var defeated := [0]
	wisp.defeated.connect(func(_e): defeated[0] += 1)
	wisp.health.apply_damage(30.0)
	var shot_count := shots.size()
	_step(wisp, 300)
	_check(wisp.is_dead() and defeated[0] == 1 and shots.size() == shot_count, "defeated wisp stops casting")
	await _free_arena()


# --- integration -----------------------------------------------------------------

func _test_integration() -> void:
	print("[Integration: courier vs enemies]")
	_new_arena()
	var player := _spawn_player(Vector3.ZERO)
	var combat := CombatController.find_on(player)
	var carrier := PackageCarrier.find_on(player)
	carrier.simulate_mechanics = false
	var health := combat.health
	var wisp := _spawn_enemy(WISP_SCENE, Vector3(0.0, 0.0, -6.0)) as FrostWisp
	wisp.free_on_death = false
	await _physics_frames(3)
	_check(wisp.find_target() == player, "enemies find the courier through the combat_player group")
	wisp.fire_shard(player.global_position + Vector3.UP * wisp.aim_height)
	await _physics_frames(50)
	_check(is_equal_approx(health.get_health(), 100.0 - wisp.shard_damage), "frost shard damages the courier through Combat/Health")
	var parcel := PackageInstance.new(load(PARCEL))
	carrier.pick_up(parcel)
	combat.set_package_shield_enabled(true)
	wisp.fire_shard(player.global_position + Vector3.UP * wisp.aim_height)
	await _physics_frames(50)
	_check(is_equal_approx(health.get_health(), 100.0 - wisp.shard_damage) and is_equal_approx(combat.get_shield_durability(), 60.0 - wisp.shard_damage) and is_equal_approx(parcel.integrity, 100.0), "Package Shield absorbs a frost shard")

	var hits := []
	combat.target_hit.connect(func(t, a): hits.append([t, a]))
	combat.try_magic_bolt(Vector3.FORWARD)
	await _physics_frames(25)
	combat.advance(1.0)
	combat.try_magic_bolt(Vector3.FORWARD)
	await _physics_frames(25)
	_check(wisp.is_dead() and hits.size() == 2 and hits[0][0] == wisp, "two Magic Bolts defeat a Frost Wisp")

	combat.set_package_shield_enabled(false)
	var slime := _spawn_enemy(SLIME_SCENE, Vector3(1.0, 0.0, 0.0)) as ForestSlime
	slime.free_on_death = false
	slime.attack_windup = 0.05
	await _physics_frames(3)
	var attacks := []
	slime.attacked.connect(func(t, landed): attacks.append([t, landed]))
	_step(slime, 2)
	_check(slime.state == ES.WINDUP, "slime next to the courier winds up")
	var hp := health.get_health()
	combat.try_dash(Vector3.RIGHT)
	for i in 20:
		combat.advance(STEP)
		slime.advance(STEP)
	_check(_last(attacks) == [player, false] and is_equal_approx(health.get_health(), hp), "dashing through a strike negates it")
	var steps := 0
	while (attacks.is_empty() or attacks.back()[1] == false) and steps < 600:
		slime.advance(STEP)
		steps += 1
	_check(is_equal_approx(health.get_health(), hp - slime.contact_damage), "slime catches up and lands a hit after the dash")
	_check(is_equal_approx(parcel.integrity, 100.0 - slime.contact_damage * combat.package_impact_per_damage), "carried package takes impact from the unshielded hit (got %.2f)" % parcel.integrity)

	combat.set_package_shield_enabled(true)
	health.apply_damage(1000.0)
	_check(health.is_dead() and not combat.is_shield_active(), "courier dies (lethal overflow breaks the shield)")
	combat.advance(5.0)
	_check(not combat.try_magic_bolt() and not combat.try_dash() and not combat.set_package_shield_enabled(true), "a dead courier cannot use abilities")
	_step(slime, 120)
	_check(slime.state == ES.IDLE, "enemies stop attacking a dead courier")
	health.reset()
	_check(combat.try_magic_bolt(Vector3.LEFT) and combat.try_dash(Vector3.LEFT), "abilities return after respawn")
	for i in 20:
		combat.advance(STEP)
	await _free_arena()


func _slime_duel() -> Array:
	_new_arena()
	var dummy := _dummy(Vector3.ZERO)
	var slime := _spawn_enemy(SLIME_SCENE, Vector3(6.0, 0.0, 2.0))
	slime.target = dummy
	slime.free_on_death = false
	await _physics_frames(3)
	var landed := [0]
	slime.attacked.connect(func(_t, ok): landed[0] += 1 if ok else 0)
	for i in 600:
		slime.advance(STEP)
		if i == 300:
			dummy.global_position = Vector3(-1.5, 0.0, 1.0)
	var result := [slime.global_position, CombatHealth.find_on(dummy).get_health(), slime.state, landed[0]]
	await _free_arena()
	return result


func _test_determinism() -> void:
	print("[Determinism]")
	var a: Array = await _slime_duel()
	var b: Array = await _slime_duel()
	_check(a == b, "identical slime duels give identical results %s" % [a])
	_check(int(a[3]) > 0 and float(a[1]) < 100.0, "the duel produced hits (%d)" % int(a[3]))


# --- sandbox & regressions -------------------------------------------------------

func _test_sandbox() -> void:
	print("[Combat sandbox]")
	var packed := load(SANDBOX) as PackedScene
	_check(packed != null and packed.can_instantiate(), "sandbox scene loads")
	if packed == null:
		return
	var sandbox := packed.instantiate() as CombatSandbox
	root.add_child(sandbox)
	current_scene = sandbox
	await _physics_frames(5)
	var slimes := 0
	var wisps := 0
	for enemy in sandbox.enemies_root.get_children():
		if enemy is ForestSlime:
			slimes += 1
		elif enemy is FrostWisp:
			wisps += 1
	_check(slimes == 2 and wisps == 2, "sandbox spawns 2 Forest Slimes and 2 Frost Wisps")
	_check(sandbox.combat != null and sandbox.combat.is_carrying_package(), "courier starts carrying a parcel")
	_check(sandbox.camera_rig.target == sandbox.player, "camera follows the courier")
	_check(sandbox.combat.set_package_shield_enabled(true), "Package Shield can be raised in the sandbox")
	sandbox.player_health.apply_damage(1000.0)
	_check(sandbox.player_health.is_dead() and not sandbox.player.input_enabled, "courier death disables input")
	sandbox.respawn_player()
	_check(not sandbox.player_health.is_dead() and sandbox.player.input_enabled and is_equal_approx(sandbox.player_health.get_health(), 100.0), "respawn restores the courier")
	var first: Enemy = sandbox.enemies_root.get_child(0)
	var count := sandbox.enemies_root.get_child_count()
	var spawn := first.global_transform
	first.health.apply_damage(1000.0)
	var replacement := sandbox.respawn_enemy({"scene": first.scene_file_path, "transform": spawn})
	_check(replacement != null and replacement.global_transform.is_equal_approx(spawn) and sandbox.enemies_root.get_child_count() == count + 1, "defeated enemies respawn at their spawn point")
	sandbox.queue_free()
	await process_frame

	var allowed := ["res://scripts/combat/", "res://scenes/player/", "res://scenes/camera/", "res://scenes/gameplay/combat/"]
	var outside := []
	for dependency: String in ResourceLoader.get_dependencies(SANDBOX):
		var parts := dependency.split("::")
		var path: String = parts[parts.size() - 1]
		var ok := false
		for prefix in allowed:
			if path.begins_with(prefix):
				ok = true
		if not ok:
			outside.append(path)
	_check(outside.is_empty(), "sandbox depends only on combat, player and camera scenes %s" % [outside])


func _find_player(node: Node) -> PlayerController:
	if node is PlayerController:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _test_regressions() -> void:
	print("[Regressions]")
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerController
	for path in [^"MovementComponent", ^"FacingComponent", ^"InteractionDetector", ^"PackageCarrier", ^"Visual", ^"CollisionShape3D"]:
		_check(player.has_node(path), "player.tscn still has %s" % path)
	_check(player.collision_layer == 2 and player.collision_mask == 5, "player collision layers unchanged")
	player.free()
	var village := load(VILLAGE) as PackedScene
	_check(village != null and village.can_instantiate(), "village scene still loads")
	if village != null:
		var instance := village.instantiate()
		var village_player := _find_player(instance)
		_check(village_player != null and CombatController.find_on(village_player) != null, "village courier inherits the Combat child")
		instance.free()
