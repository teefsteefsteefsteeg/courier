class_name WeaponUltimates
extends Node
## The +5 weapon ultimates (Phase 8): [C] (weapon_ultimate) releases the held weapon's
## element outward. Only a +5 weapon has one; normal attacks (Space) never trigger it.
##   sword  FLAME SLASH    a wave of fire travels forward 12 m; every enemy it passes is
##                         burned once (directional: nothing behind or beside the wave)
##   axe    EARTHQUAKE     a shockwave expands from the chop point to 7 m; every enemy the
##                         front passes takes damage once and is staggered (if it can be)
##   bow    THUNDER ARROW  a charged arrow; where it hits, lightning strikes and then chains
##                         to up to 3 nearby enemies, each struck once
##   staff  ARCANE STORM   a storm over the nearest enemy (or ahead): 6 timed arcane strikes
##                         in a 4.5 m circle; each strike hits each enemy at most once. Costs
##                         MP (see mana source below) and has the longest cooldown
## Damage scales with the weapon's own (enhanced) damage from CombatController, so
## enhancement, armor and defense rules stay the same. Hits go through CombatHealth and are
## reported as CombatController.target_hit (damage feedback, impact effects).
## Costs: every ultimate needs CourierVitals.ULTIMATE_RAGE_COST rage (built by normal hits;
## group "courier_rage"), the Arcane Storm also mp_cost MP (group "courier_mana"). Without
## those services (bare test scenes) only the cooldown applies. Damage also takes the
## courier's buff multiplier (CombatController.damage_multiplier).
## World-space effects (GroundFx): the slash leaves burning ground and scorch marks and ends
## in an explosion; the quake opens glowing fissures with shockwave rings, flying rocks and
## dust; the thunder arrow calls lightning down from the sky on every target; the storm
## draws a rune circle on the terrain and strikes with violet lightning. Hit enemies show
## their element (burning, stunned, shocked, arcane) and the camera shakes.
## Lives in GameplayServices; finds the player like AttackEffects.

signal ultimate_used(skill: StringName)
signal ultimate_blocked(skill: StringName, reason: StringName)
## Every damage event of a skill (for tests and feedback).
signal skill_hit(skill: StringName, target: Node, amount: float)
signal effect_spawned(kind: StringName, effect: Node3D)

const GROUP := &"weapon_ultimates"
const MANA_GROUP := &"courier_mana"
const RAGE_GROUP := &"courier_rage"
const FIRE_TINT := Color(1.0, 0.5, 0.15)
const EARTH_TINT := Color(1.0, 0.55, 0.18)
const THUNDER_TINT := Color(0.55, 0.8, 1.0)
const ARCANE_TINT := Color(0.72, 0.45, 1.0)
const WAVE := preload("res://assets/vfx/BinbunVFX_Magic/magic_projectiles/effects/mprojectile_wave/mprojectile_wave_vfx_01.tscn")
const BOLT := preload("res://assets/vfx/BinbunVFX_Magic/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_01.tscn")
const VORTEX := preload("res://assets/vfx/boss_tornado/vortex.tscn")
const ARROW := preload("res://scenes/gameplay/combat/arrow.tscn")
const FIRE_SHEET := "res://assets/vfx/boss/fire_8x8.png"
## Where the sample's blue tornado layers sit (minus their base height), and the widest
## layer's radius at scale 1 (tornado.obj is 3.65 m across x 2.4 in the sample).
const VORTEX_CENTRE := Vector3(5.58733, -5.6, -3.91603)
const VORTEX_RADIUS := 8.7

## Per weapon class: id, name, cooldown (s), damage factor (x the weapon's damage), extras.
const SKILLS := {
	ItemDefinition.WeaponType.SWORD: {"id": &"flame_slash", "name": "Flame Slash", "cooldown": 8.0, "factor": 2.2,
		"range": 12.0, "speed": 15.0, "half_width": 1.5},
	ItemDefinition.WeaponType.AXE: {"id": &"earthquake", "name": "Earthquake", "cooldown": 10.0, "factor": 1.8,
		"radius": 7.0, "duration": 0.7, "stagger": 1.2},
	ItemDefinition.WeaponType.BOW: {"id": &"thunder_arrow", "name": "Thunder Arrow", "cooldown": 9.0, "factor": 2.0,
		"chain_factor": 1.3, "chain_radius": 7.0, "chain_count": 3, "chain_delay": 0.15},
	ItemDefinition.WeaponType.STAFF: {"id": &"arcane_storm", "name": "Arcane Storm", "cooldown": 12.0, "factor": 1.1,
		"radius": 4.5, "strikes": 6, "interval": 0.38, "strike_radius": 1.6, "mp_cost": 30.0, "reach": 10.0},
}

@export var inventory: CourierInventory

var combat: CombatController = null
## Seconds left per skill id.
var cooldowns: Dictionary = {}
## Skills in flight (waves, quakes, arrows, storms), freed when they finish.
var active: Array[Node] = []
var _rng := RandomNumberGenerator.new()


static func find(tree: SceneTree) -> WeaponUltimates:
	return tree.get_first_node_in_group(GROUP) as WeaponUltimates if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	for id in cooldowns.keys():
		cooldowns[id] = maxf(float(cooldowns[id]) - delta, 0.0)
	for i in range(active.size() - 1, -1, -1):
		if not is_instance_valid(active[i]):
			active.remove_at(i)
	if combat != null and is_instance_valid(combat):
		return
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	var player := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP)
	combat = CombatController.find_on(player) if player != null else null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"weapon_ultimate"):
		use()
		get_viewport().set_input_as_handled()


## The skill of the weapon in hand ({} when it has none: no weapon, a tool, or below +5).
func current_skill() -> Dictionary:
	var item := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) if inventory != null else null
	if item == null or not item.is_weapon() or not SKILLS.has(item.weapon_type):
		return {}
	if inventory.get_enhancement(item.item_id) < Enhancement.MAX_LEVEL:
		return {}
	return SKILLS[item.weapon_type]


## Seconds until the weapon in hand's skill is ready (0 when ready or none).
func get_cooldown_remaining() -> float:
	var skill := current_skill()
	return float(cooldowns.get(skill.get("id", &""), 0.0)) if not skill.is_empty() else 0.0


## Releases the held weapon's ultimate. Returns true when it fired.
func use() -> bool:
	if combat == null or not is_instance_valid(combat):
		return false
	var item := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND)
	var skill := current_skill()
	if skill.is_empty():
		var reason := &"no_weapon" if item == null or not item.is_weapon() else &"needs_plus5"
		_notify("Ultimates need a +5 weapon in hand." if reason == &"needs_plus5" else "Hold a +5 weapon to use its ultimate.")
		ultimate_blocked.emit(&"", reason)
		return false
	var id: StringName = skill["id"]
	var body := combat.get_parent() as PlayerController
	if body == null or not body.input_enabled or combat.health == null or combat.health.is_dead():
		ultimate_blocked.emit(id, &"busy")
		return false
	if float(cooldowns.get(id, 0.0)) > 0.0:
		ultimate_blocked.emit(id, &"cooldown")
		return false
	var rage := get_tree().get_first_node_in_group(RAGE_GROUP)
	if rage != null and not bool(rage.call(&"has_rage", get_rage_cost())):
		_notify("%s needs %d rage: land hits to build it." % [skill["name"], roundi(get_rage_cost())])
		ultimate_blocked.emit(id, &"rage")
		return false
	if skill.has("mp_cost") and not _spend_mana(float(skill["mp_cost"])):
		_notify("Not enough MP for %s." % skill["name"])
		ultimate_blocked.emit(id, &"mana")
		return false
	if rage != null:
		rage.call(&"spend_rage", get_rage_cost())
	cooldowns[id] = float(skill["cooldown"])
	var aim := combat.get_aim_direction()
	match item.weapon_type:
		ItemDefinition.WeaponType.SWORD:
			_flame_slash(body, aim, skill)
		ItemDefinition.WeaponType.AXE:
			_earthquake(body, aim, skill)
		ItemDefinition.WeaponType.BOW:
			_thunder_arrow(body, aim, skill)
		ItemDefinition.WeaponType.STAFF:
			_arcane_storm(body, aim, skill)
	ultimate_used.emit(id)
	return true


## Rage every ultimate costs.
func get_rage_cost() -> float:
	return CourierVitals.ULTIMATE_RAGE_COST


## True when the courier could release the held weapon's ultimate now (cooldown, rage and
## MP all allow it), for the HUD's "ready" state.
func is_ready() -> bool:
	var skill := current_skill()
	if skill.is_empty() or float(cooldowns.get(skill["id"], 0.0)) > 0.0:
		return false
	var rage := get_tree().get_first_node_in_group(RAGE_GROUP)
	if rage != null and not bool(rage.call(&"has_rage", get_rage_cost())):
		return false
	var mana := get_tree().get_first_node_in_group(MANA_GROUP)
	return not skill.has("mp_cost") or mana == null or float(mana.call(&"get_mana")) >= float(skill["mp_cost"])


## True when the MP was paid, or when there is no MP source (see the class notes).
func _spend_mana(amount: float) -> bool:
	var source := get_tree().get_first_node_in_group(MANA_GROUP)
	if source == null or not source.has_method(&"spend"):
		return true
	return bool(source.call(&"spend", amount))


func _hit(skill: StringName, target: Node, amount: float, from: Vector3) -> bool:
	var health := CombatHealth.find_on(target)
	if health == null or health.is_dead() or not health.apply_damage(amount * combat.damage_multiplier, from):
		return false
	combat.target_hit.emit(target, health.last_damage_taken)
	skill_hit.emit(skill, target, health.last_damage_taken)
	return true


## Enemies (CombatHealth bodies on the enemy layer) within radius of a point.
func enemies_near(point: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var body := combat.get_parent() as Node3D
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = CombatController.ENEMY_LAYER
	query.exclude = [body.get_rid()]
	for result: Dictionary in body.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var target := result.collider as Node3D
		if target != null and not found.has(target) and CombatHealth.find_on(target) != null and not CombatHealth.find_on(target).is_dead():
			found.append(target)
	return found


# --- Flame Slash ---------------------------------------------------------------------

func _flame_slash(body: Node3D, aim: Vector3, skill: Dictionary) -> void:
	var damage := combat.melee_damage * float(skill["factor"])
	var wave := Node3D.new()
	wave.name = "FlameSlash"
	body.get_parent().add_child(wave)
	wave.global_position = body.global_position + aim * 0.8 + Vector3.UP * 0.6
	wave.global_basis = Basis(-aim, Vector3.UP, (-aim).cross(Vector3.UP))
	var vfx := WAVE.instantiate() as Node3D
	vfx.name = "Wave"
	vfx.scale = Vector3(2.2, 2.6, 2.6)
	wave.add_child(vfx)
	vfx.set(&"primary_color", Color(1.0, 0.85, 0.5))
	vfx.set(&"secondary_color", Color(1.0, 0.45, 0.08))
	vfx.set(&"tertiary_color", Color(0.7, 0.12, 0.02))
	vfx.set(&"light_color", Color(1.0, 0.5, 0.15))
	var side := aim.cross(Vector3.UP).normalized()
	for i in 3:
		var flame := VfxStrip.create(&"flame" if i % 2 == 0 else &"flame_b", 1.1, Color.WHITE, true, i * 2)
		flame.name = "Flame%d" % i
		flame.offset.y = 20.0
		wave.add_child(flame)
		flame.position = Vector3(0.0, -0.3, (i - 1) * float(skill["half_width"]) * 0.7)
	wave.add_child(_fire_stream(0.9))
	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = FIRE_TINT
	glow.light_energy = 4.0
	glow.omni_range = 6.0
	wave.add_child(glow)
	active.append(wave)
	effect_spawned.emit(&"flame_slash", wave)
	var parent := body.get_parent()
	GroundFx.shake(body, 0.08, 0.25)
	var hit: Array[Node] = []
	var travelled := 0.0
	var next_patch := 0.0
	var space := body.get_world_3d().direct_space_state
	while travelled < float(skill["range"]) and is_instance_valid(wave):
		await get_tree().physics_frame
		if not is_instance_valid(wave):
			return
		var step := float(skill["speed"]) * get_physics_process_delta_time()
		var from := wave.global_position
		# A wall or tree stops the wave.
		var block := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + aim * step, CombatController.WORLD_LAYER))
		if not block.is_empty():
			break
		wave.global_position = from + aim * step
		travelled += step
		for target in enemies_near(wave.global_position, float(skill["half_width"]) + 0.6):
			if hit.has(target):
				continue
			var offset := target.global_position - wave.global_position
			offset.y = 0.0
			# The wave's own band only: within half its width across, and not behind it.
			if absf(offset.dot(side)) <= float(skill["half_width"]) + 0.5 and offset.dot(aim) > -1.2:
				hit.append(target)
				if _hit(&"flame_slash", target, damage, wave.global_position):
					GroundFx.status(target, &"burn", 2.5)
					GroundFx.sparks(parent, target.global_position + Vector3.UP * 0.8, FIRE_TINT, 16)
		# The ground it passes keeps burning: a flame patch and a scorch mark every 0.9 m.
		if travelled >= next_patch:
			var ground := ground_point(wave.global_position)
			effect_spawned.emit(&"flame_trail", GroundFx.flame_patch(parent, ground, 0.9, 1.4))
			GroundFx.scorch(parent, ground, 1.8, 3.5)
			next_patch += 0.9
	if is_instance_valid(wave):
		var end := ground_point(wave.global_position)
		effect_spawned.emit(&"flame_explosion", GroundFx.explosion(parent, end, 1.8, FIRE_TINT))
		GroundFx.shake(body, 0.18, 0.35)
		_fade_out(wave, 0.25)


# --- Earthquake ----------------------------------------------------------------------

func _earthquake(body: Node3D, aim: Vector3, skill: Dictionary) -> void:
	var damage := combat.melee_damage * float(skill["factor"])
	var centre := body.global_position + aim * 1.3
	centre.y = body.global_position.y
	centre = ground_point(centre + Vector3.UP * 0.5)
	var radius := float(skill["radius"])
	var duration := float(skill["duration"])
	var parent := body.get_parent()
	var quake := Node3D.new()
	quake.name = "Earthquake"
	parent.add_child(quake)
	quake.global_position = centre + Vector3.UP * 0.06
	# Glowing fissures that open to the full radius, three shockwave rings running out
	# over the ground, rocks thrown up, dust, a blast at the centre and a hard shake.
	var cracks := GroundFx.cracks(quake, centre, radius * 2.0, EARTH_TINT, duration * 0.6, 3.2)
	cracks.name = "Cracks"
	for i in 3:
		var ring_delay := i * duration * 0.22
		get_tree().create_timer(ring_delay).timeout.connect(func() -> void:
			if is_instance_valid(quake):
				effect_spawned.emit(&"quake_ring", GroundFx.shock_ring(quake, centre, radius * (1.0 - i * 0.12), duration * 0.9, EARTH_TINT if i == 0 else Color(0.85, 0.7, 0.5), 2.5 - i * 0.6)))
	_burst_strip(quake, &"quake_blast", 2.6, Color.WHITE, centre + Vector3.UP * 0.8)
	effect_spawned.emit(&"quake_debris", GroundFx.debris(quake, centre, 26, 1.4, 0.24))
	GroundFx.dust_ring(quake, centre, 1.5)
	GroundFx.flash(quake, centre + Vector3.UP * 1.0, EARTH_TINT, 5.0, radius * 1.4, 0.5)
	GroundFx.shake(body, 0.35, 0.7)
	active.append(quake)
	effect_spawned.emit(&"earthquake", quake)
	var hit: Array[Node] = []
	var elapsed := 0.0
	var next_ring := 0.0
	while elapsed < duration and is_instance_valid(quake):
		await get_tree().physics_frame
		if not is_instance_valid(quake):
			return
		elapsed += get_physics_process_delta_time()
		var front := radius * minf(elapsed / duration, 1.0)
		# Dust and rocks burst up along the expanding front.
		if front >= next_ring:
			GroundFx.dust_ring(quake, centre, maxf(front, 1.0))
			if front > 1.0:
				var angle := _rng.randf() * TAU
				GroundFx.debris(quake, centre + Vector3(cos(angle), 0.0, sin(angle)) * front, 8, 0.6, 0.18)
			next_ring += 2.2
		for target in enemies_near(centre, front + 0.5):
			if hit.has(target):
				continue
			hit.append(target)
			if _hit(&"earthquake", target, damage, centre):
				GroundFx.debris(quake, target.global_position, 6, 0.4, 0.16)
				if target.has_method(&"stagger") and bool(target.call(&"stagger", float(skill["stagger"]))):
					GroundFx.status(target, &"stun", float(skill["stagger"]))
	# Linger for the fissures and rocks, then free.
	if is_instance_valid(quake):
		var linger := quake.create_tween()
		linger.tween_interval(3.6)
		linger.tween_callback(quake.queue_free)


## The ground under point (the first world surface within 3 m below it), or point lowered
## to the courier's feet height when there is none.
func ground_point(point: Vector3) -> Vector3:
	var body := combat.get_parent() as Node3D if combat != null else null
	if body == null or not body.is_inside_tree():
		return point
	var from := point + Vector3.UP * 1.5
	var hit := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * 3.0, CombatController.WORLD_LAYER))
	return hit["position"] if not hit.is_empty() else Vector3(point.x, body.global_position.y, point.z)


# --- Thunder Arrow -------------------------------------------------------------------

func _thunder_arrow(body: Node3D, aim: Vector3, skill: Dictionary) -> void:
	var arrow := ARROW.instantiate() as CombatProjectile
	arrow.name = "ThunderArrow"
	arrow.damage = combat.arrow_damage * float(skill["factor"])
	arrow.speed = combat.arrow_speed * 1.2
	arrow.max_distance = combat.arrow_range
	arrow.collision_mask = combat.bolt_collision_mask
	arrow.direction = aim
	arrow.source = body
	body.get_parent().add_child(arrow)
	var origin := body.global_position + Vector3.UP * combat.bolt_spawn_height + aim * combat.bolt_spawn_forward
	arrow.global_position = origin
	arrow.look_at(origin + aim, Vector3.UP)
	arrow.reset_physics_interpolation()
	var charge := VfxStrip.create(&"arc_ring", 1.3, Color(0.7, 0.92, 1.0, 1.0), true)
	charge.name = "Charge"
	arrow.add_child(charge)
	var aura := VfxStrip.create(&"aura", 1.0, Color(0.6, 0.85, 1.0, 1.0), true, 4)
	aura.name = "Aura"
	arrow.add_child(aura)
	active.append(arrow)
	effect_spawned.emit(&"thunder_arrow", arrow)
	var parent := body.get_parent()
	arrow.hit.connect(func(target: Node, amount: float) -> void:
		combat.target_hit.emit(target, amount)
		skill_hit.emit(&"thunder_arrow", target, amount)
		_chain_lightning(parent, target as Node3D, skill))
	arrow.expired.connect(func(reason: StringName) -> void:
		if reason != CombatProjectile.REASON_HIT and is_instance_valid(arrow):
			_strike_at(parent, arrow.global_position))
	var spark := OmniLight3D.new()
	spark.name = "ChargeLight"
	spark.light_color = THUNDER_TINT
	spark.light_energy = 2.5
	spark.omni_range = 4.0
	arrow.add_child(spark)


## Lightning on the struck target, then on up to chain_count other enemies nearby, nearest
## first, each once.
func _chain_lightning(parent: Node, first: Node3D, skill: Dictionary) -> void:
	if first == null or not is_instance_valid(first):
		return
	var damage := combat.arrow_damage * float(skill["chain_factor"])
	var struck: Array[Node] = [first]
	var previous := first.global_position
	_strike_at(parent, previous)
	GroundFx.status(first, &"shock", 1.5)
	for i in int(skill["chain_count"]):
		await get_tree().create_timer(float(skill["chain_delay"])).timeout
		if not is_instance_valid(parent):
			return
		var candidates := enemies_near(previous, float(skill["chain_radius"])).filter(func(target: Node3D) -> bool: return not struck.has(target))
		if candidates.is_empty():
			return
		candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(previous) < b.global_position.distance_squared_to(previous))
		var next := candidates[0] as Node3D
		struck.append(next)
		_bolt_between(parent, previous + Vector3.UP * 0.8, next.global_position + Vector3.UP * 0.8)
		_strike_at(parent, next.global_position, 0.75)
		if _hit(&"thunder_arrow_chain", next, damage, previous):
			GroundFx.status(next, &"shock", 1.5)
		previous = next.global_position


## Lightning from the sky onto the ground at `at` (a burn mark, a spark ring, a light flash
## and a small shake come with it).
func _strike_at(parent: Node, at: Vector3, width: float = 1.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var ground := ground_point(at)
	var strike := GroundFx.lightning_strike(parent, ground, THUNDER_TINT, 14.0, width)
	effect_spawned.emit(&"lightning_strike", strike)
	_burst_strip(parent, &"arc_ring", 1.6 * width, Color(0.65, 0.9, 1.0, 1.0), ground + Vector3.UP * 0.4)
	GroundFx.shake(parent, 0.2 * width, 0.3)


## A jagged, flickering arc of electricity between two points (the chain's jump).
func _bolt_between(parent: Node, from: Vector3, to: Vector3) -> void:
	var bolt := GroundFx.arc(parent, from, to, THUNDER_TINT, 0.7)
	bolt.name = "ChainBolt"
	effect_spawned.emit(&"chain_bolt", bolt)


# --- Arcane Storm --------------------------------------------------------------------

func _arcane_storm(body: Node3D, aim: Vector3, skill: Dictionary) -> void:
	var radius := float(skill["radius"])
	var centre := body.global_position + aim * 6.0
	var nearest := INF
	for target in enemies_near(body.global_position, float(skill["reach"])):
		var d := target.global_position.distance_to(body.global_position)
		if d < nearest:
			nearest = d
			centre = target.global_position
	centre = ground_point(centre + Vector3.UP * 0.5)
	var storm := Node3D.new()
	storm.name = "ArcaneStorm"
	body.get_parent().add_child(storm)
	storm.global_position = centre
	var lasting := float(skill["strikes"]) * float(skill["interval"]) + 1.2
	# A rune circle drawn on the terrain itself (a decal, so it follows the slope).
	var ring := GroundFx.rune_circle(storm, centre, radius, ARCANE_TINT, lasting)
	ring.name = "Circle"
	effect_spawned.emit(&"rune_circle", ring)
	GroundFx.flash(storm, centre + Vector3.UP * 2.5, ARCANE_TINT, 3.0, radius * 2.5, lasting)
	var vortex := _vortex(radius * 0.7 / VORTEX_RADIUS, Color(0.65, 0.45, 1.0))
	storm.add_child(vortex)
	active.append(storm)
	effect_spawned.emit(&"arcane_storm", storm)
	var damage := combat.bolt_damage * float(skill["factor"])
	for i in int(skill["strikes"]):
		await get_tree().create_timer(float(skill["interval"])).timeout
		if not is_instance_valid(storm):
			return
		var inside := enemies_near(centre, radius)
		var point: Vector3
		if not inside.is_empty():
			var target := inside[i % inside.size()]
			point = target.global_position + Vector3(_rng.randf_range(-0.4, 0.4), 0.0, _rng.randf_range(-0.4, 0.4))
		else:
			var angle := _rng.randf() * TAU
			point = centre + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.0, radius * 0.85)
		_storm_strike(storm, point, damage, float(skill["strike_radius"]))
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(storm):
		_fade_out(storm, 0.6)


## One arcane bolt falls onto point and bursts; each enemy within reach is hit once.
func _storm_strike(storm: Node3D, point: Vector3, damage: float, reach: float) -> void:
	var bolt := BOLT.instantiate() as Node3D
	bolt.name = "StormBolt"
	storm.add_child(bolt)
	bolt.global_position = point + Vector3.UP * 7.0
	# The projectile points along -X: aim it down.
	bolt.global_basis = Basis(Vector3.UP, Vector3.RIGHT, Vector3.UP.cross(Vector3.RIGHT)).scaled(Vector3.ONE * 1.6)
	bolt.set(&"primary_color", Color(0.9, 0.8, 1.0))
	bolt.set(&"secondary_color", Color(0.65, 0.4, 1.0))
	bolt.set(&"tertiary_color", Color(0.3, 0.1, 0.6))
	bolt.set(&"light_color", Color(0.7, 0.5, 1.0))
	effect_spawned.emit(&"storm_bolt", bolt)
	var fall := bolt.create_tween()
	fall.tween_property(bolt, ^"global_position", point + Vector3.UP * 0.3, 0.22)
	await fall.finished
	if not is_instance_valid(storm):
		return
	bolt.queue_free()
	var ground := ground_point(point)
	effect_spawned.emit(&"storm_lightning", GroundFx.lightning_strike(storm, ground, ARCANE_TINT, 10.0, 0.7))
	_burst_strip(storm, &"light_burst", 2.2, Color(0.85, 0.75, 1.0, 1.0), ground + Vector3.UP * 0.6)
	_burst_strip(storm, &"warp", 2.0, Color(0.75, 0.55, 1.0, 1.0), ground + Vector3.UP * 0.3)
	GroundFx.shake(storm, 0.12, 0.2)
	for target in enemies_near(point, reach):
		if _hit(&"arcane_storm", target, damage, point):
			GroundFx.status(target, &"arcane", 1.2)


## The swirling storm column: the three layers of the bossEffect sample's blue tornado
## (its showcase scene holds several tornadoes side by side), centred, scaled and tinted.
func _vortex(scale: float, tint: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Vortex"
	var sample := VORTEX.instantiate()
	var blue := sample.get_node(^"tornado Blue")
	for layer_name in ["twhite", "twhite2", "twhite3"]:
		var layer := blue.get_node(layer_name) as MeshInstance3D
		blue.remove_child(layer)
		layer.owner = null
		layer.position -= VORTEX_CENTRE
		var material := layer.get_active_material(0) as ShaderMaterial
		if material != null:
			material = material.duplicate() as ShaderMaterial
			material.set_shader_parameter(&"ColorParameter", tint)
			material.set_shader_parameter(&"intesityColor", 4.0)
			layer.material_override = material
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(layer)
	sample.free()
	pivot.scale = Vector3.ONE * scale
	return pivot


# --- helpers ---------------------------------------------------------------------------

## A one-shot flipbook at a point under parent (frees itself).
func _burst_strip(parent: Node, source: StringName, size: float, tint: Color, at: Vector3) -> VfxStrip:
	if parent == null or not is_instance_valid(parent):
		return null
	var strip := VfxStrip.create(source, size, tint, false)
	strip.name = "Fx_" + String(source)
	strip.free_on_finish = true
	parent.add_child(strip)
	strip.global_position = at
	return strip


## Animated fire (the 8x8 flipbook) streaming up behind a moving effect.
func _fire_stream(size: float) -> CPUParticles3D:
	var fire := CPUParticles3D.new()
	fire.name = "Fire"
	fire.amount = 24
	fire.lifetime = 0.6
	fire.local_coords = false
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire.emission_box_extents = Vector3(0.3, 0.2, 1.3)
	fire.direction = Vector3.UP
	fire.spread = 20.0
	fire.initial_velocity_min = 0.8
	fire.initial_velocity_max = 1.8
	fire.gravity = Vector3(0, 1.0, 0)
	fire.anim_speed_min = 1.0
	fire.anim_speed_max = 1.0
	fire.scale_amount_min = 0.8
	fire.scale_amount_max = 1.5
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := EnhancementGlow._additive(load(FIRE_SHEET) as Texture2D, Color.WHITE)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.particles_anim_h_frames = 8
	material.particles_anim_v_frames = 8
	material.particles_anim_loop = false
	material.vertex_color_use_as_albedo = true
	quad.material = material
	fire.mesh = quad
	# The sheet is white: the ramp gives it fire colours.
	fire.color_ramp = GroundFx.fire_ramp(FIRE_TINT)
	return fire


func _fade_out(node: Node3D, seconds: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(node, ^"scale", node.scale * 0.2, seconds)
	tween.tween_callback(node.queue_free)


func _notify(text: String) -> void:
	var notices := get_tree().root.find_children("*", "QuestNotification", true, false)
	if not notices.is_empty():
		(notices[0] as QuestNotification).push_message(text, QuestNotification.KIND_INFO)
