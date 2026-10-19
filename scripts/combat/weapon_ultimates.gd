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
## MP: the game has no MP yet (Phase 8 milestone 6). A node in group "courier_mana" with
## spend(amount) -> bool is charged when present; without one the storm has only its
## cooldown (mp_cost is still reported).
## Lives in GameplayServices; finds the player like AttackEffects.

signal ultimate_used(skill: StringName)
signal ultimate_blocked(skill: StringName, reason: StringName)
## Every damage event of a skill (for tests and feedback).
signal skill_hit(skill: StringName, target: Node, amount: float)
signal effect_spawned(kind: StringName, effect: Node3D)

const GROUP := &"weapon_ultimates"
const MANA_GROUP := &"courier_mana"
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
	if skill.has("mp_cost") and not _spend_mana(float(skill["mp_cost"])):
		_notify("Not enough MP for %s." % skill["name"])
		ultimate_blocked.emit(id, &"mana")
		return false
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


## True when the MP was paid, or when there is no MP source yet (see the class notes).
func _spend_mana(amount: float) -> bool:
	var source := get_tree().get_first_node_in_group(MANA_GROUP)
	if source == null or not source.has_method(&"spend"):
		return true
	return bool(source.call(&"spend", amount))


func _hit(skill: StringName, target: Node, amount: float, from: Vector3) -> bool:
	var health := CombatHealth.find_on(target)
	if health == null or health.is_dead() or not health.apply_damage(amount, from):
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
	active.append(wave)
	effect_spawned.emit(&"flame_slash", wave)
	var hit: Array[Node] = []
	var travelled := 0.0
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
				_hit(&"flame_slash", target, damage, wave.global_position)
	if is_instance_valid(wave):
		_burst_strip(wave.get_parent(), &"blast", 1.8, Color.WHITE, wave.global_position)
		_fade_out(wave, 0.25)


# --- Earthquake ----------------------------------------------------------------------

func _earthquake(body: Node3D, aim: Vector3, skill: Dictionary) -> void:
	var damage := combat.melee_damage * float(skill["factor"])
	var centre := body.global_position + aim * 1.3
	centre.y = body.global_position.y
	var quake := Node3D.new()
	quake.name = "Earthquake"
	body.get_parent().add_child(quake)
	quake.global_position = centre + Vector3.UP * 0.06
	var cracks := MeshInstance3D.new()
	cracks.name = "Cracks"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 2.0
	cracks.mesh = plane
	var crack_material := StandardMaterial3D.new()
	crack_material.albedo_texture = _crack_texture()
	crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_material.albedo_color = Color(1.0, 0.55, 0.2, 1.0)
	crack_material.emission_enabled = true
	crack_material.emission = Color(1.0, 0.4, 0.1)
	cracks.material_override = crack_material
	cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quake.add_child(cracks)
	_burst_strip(quake, &"quake_blast", 2.6, Color.WHITE, centre + Vector3.UP * 0.8)
	quake.add_child(_rock_burst())
	active.append(quake)
	effect_spawned.emit(&"earthquake", quake)
	var radius := float(skill["radius"])
	var duration := float(skill["duration"])
	var hit: Array[Node] = []
	var elapsed := 0.0
	var next_ring := 0.0
	while elapsed < duration and is_instance_valid(quake):
		await get_tree().physics_frame
		if not is_instance_valid(quake):
			return
		elapsed += get_physics_process_delta_time()
		var front := radius * minf(elapsed / duration, 1.0)
		cracks.scale = Vector3.ONE * maxf(front, 0.5)
		# Dust bursts round the expanding front.
		if front >= next_ring:
			var count := 6 + int(front)
			for i in count:
				var angle := TAU * i / count + _rng.randf_range(-0.2, 0.2)
				var at := centre + Vector3(cos(angle), 0.0, sin(angle)) * front + Vector3.UP * 0.4
				_burst_strip(quake, &"dust_ring" if i % 2 == 0 else &"rubble", 1.4, Color.WHITE if i % 2 == 0 else Color(0.78, 0.68, 0.52, 0.95), at)
			next_ring += 2.2
		for target in enemies_near(centre, front + 0.5):
			if hit.has(target):
				continue
			hit.append(target)
			if _hit(&"earthquake", target, damage, centre) and target.has_method(&"stagger"):
				target.call(&"stagger", float(skill["stagger"]))
	if is_instance_valid(quake):
		_fade_out(quake, 1.0)


func _rock_burst() -> CPUParticles3D:
	var rocks := CPUParticles3D.new()
	rocks.name = "Rocks"
	rocks.amount = 28
	rocks.lifetime = 1.0
	rocks.one_shot = true
	rocks.explosiveness = 0.9
	rocks.direction = Vector3.UP
	rocks.spread = 55.0
	rocks.initial_velocity_min = 3.5
	rocks.initial_velocity_max = 6.5
	rocks.gravity = Vector3(0, -14.0, 0)
	rocks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	rocks.emission_sphere_radius = 1.2
	rocks.scale_amount_min = 0.6
	rocks.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.35
	var material := EnhancementGlow._additive(EnhancementGlow._texture("pebble"), Color(0.55, 0.46, 0.35))
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = material
	rocks.mesh = quad
	rocks.emitting = true
	return rocks


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


## Lightning on the struck target, then on up to chain_count other enemies nearby, nearest
## first, each once.
func _chain_lightning(parent: Node, first: Node3D, skill: Dictionary) -> void:
	if first == null or not is_instance_valid(first):
		return
	var damage := combat.arrow_damage * float(skill["chain_factor"])
	var struck: Array[Node] = [first]
	var previous := first.global_position
	_strike_at(parent, previous)
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
		_strike_at(parent, next.global_position)
		_hit(&"thunder_arrow_chain", next, damage, previous)
		previous = next.global_position


func _strike_at(parent: Node, at: Vector3) -> void:
	var strike := _burst_strip(parent, &"strike", 2.4, Color.WHITE, at + Vector3.UP * 1.3)
	if strike != null:
		effect_spawned.emit(&"lightning_strike", strike)
	_burst_strip(parent, &"arc_ring", 1.6, Color(0.65, 0.9, 1.0, 1.0), at + Vector3.UP * 0.4)


## A jagged lightning ribbon between two points (fades in 0.25 s).
func _bolt_between(parent: Node, from: Vector3, to: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 8
	var points: Array[Vector3] = []
	var across := (to - from).cross(Vector3.UP).normalized()
	for i in segments + 1:
		var t := float(i) / segments
		var jitter := 0.0 if i == 0 or i == segments else _rng.randf_range(-0.45, 0.45)
		points.append(from.lerp(to, t) + across * jitter + Vector3.UP * _rng.randf_range(-0.2, 0.2) * float(i % segments != 0))
	var width := Vector3.UP * 0.09
	for i in segments:
		var a := points[i]
		var b := points[i + 1]
		for v in [a - width, b - width, b + width, a - width, b + width, a + width]:
			st.add_vertex(v)
	var bolt := MeshInstance3D.new()
	bolt.name = "ChainBolt"
	bolt.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.75, 0.92, 1.0, 1.0)
	bolt.material_override = material
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bolt)
	effect_spawned.emit(&"chain_bolt", bolt)
	var tween := bolt.create_tween()
	tween.tween_property(material, ^"albedo_color:a", 0.0, 0.3).set_delay(0.1)
	tween.tween_callback(bolt.queue_free)


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
	centre.y = body.global_position.y
	var storm := Node3D.new()
	storm.name = "ArcaneStorm"
	body.get_parent().add_child(storm)
	storm.global_position = centre
	var ring := MeshInstance3D.new()
	ring.name = "Circle"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	ring.mesh = plane
	var ring_material := EnhancementGlow._additive(EnhancementGlow._texture("rune"), Color(0.75, 0.5, 1.0, 0.95))
	ring_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	ring.material_override = ring_material
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	storm.add_child(ring)
	var spin := ring.create_tween().set_loops()
	spin.tween_property(ring, ^"rotation:y", TAU, 3.0).from(0.0)
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
	await get_tree().create_timer(0.6).timeout
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
	_burst_strip(storm, &"light_burst", 2.2, Color(0.85, 0.75, 1.0, 1.0), point + Vector3.UP * 0.6)
	_burst_strip(storm, &"warp", 2.0, Color(0.75, 0.55, 1.0, 1.0), point + Vector3.UP * 0.3)
	for target in enemies_near(point, reach):
		_hit(&"arcane_storm", target, damage, point)


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
	return fire


func _fade_out(node: Node3D, seconds: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(node, ^"scale", node.scale * 0.2, seconds)
	tween.tween_callback(node.queue_free)


func _notify(text: String) -> void:
	var notices := get_tree().root.find_children("*", "QuestNotification", true, false)
	if not notices.is_empty():
		(notices[0] as QuestNotification).push_message(text, QuestNotification.KIND_INFO)


static var _crack: ImageTexture


## Radial ground cracks (glowing lines from the centre, branching), for the Earthquake.
static func _crack_texture() -> Texture2D:
	if _crack != null:
		return _crack
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for branch in 9:
		var angle := TAU * branch / 9.0 + rng.randf_range(-0.2, 0.2)
		var p := Vector2(size, size) * 0.5
		var length := rng.randf_range(0.36, 0.48) * size
		var steps := int(length)
		for i in steps:
			angle += rng.randf_range(-0.25, 0.25)
			p += Vector2(cos(angle), sin(angle))
			var fade := 1.0 - float(i) / steps
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var q := Vector2i(p) + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < size and q.y < size:
						var core := 1.0 if dx == 0 and dy == 0 else 0.45
						var previous := image.get_pixelv(q).a
						image.set_pixelv(q, Color(1, 1, 1, maxf(previous, core * fade)))
	_crack = ImageTexture.create_from_image(image)
	return _crack
