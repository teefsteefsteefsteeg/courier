class_name AttackEffects
extends Node
## Skill effects timed to the gameplay hit (Phase 7):
## - Sword and axe: a BattleFX swing arc (Binbun, CC0) starts with the swing
##   (CombatController.melee_started) and sweeps to its fullest exactly when the hit lands,
##   melee_windup seconds later (CombatController._resolve_melee). A sword cuts a level arc,
##   the axe a vertical chop; the arc takes the weapon's enhancement colour. A cancelled
##   swing (weapon switched mid wind-up) removes its arc.
## - Melee hits and arrows: an impact flash (Gigapack strip) on the target when the damage
##   is applied (target_hit).
## - The Magic Bolt keeps its own projectile and burst (CombatVisualAdapter).
## - Phase 8 elemental rework: active effects per weapon class and level, cosmetic only
##   (damage is unchanged; the +5 skills are WeaponUltimates):
##     sword  arc in the blade's element; +2 icy streaks, +3 ember burst, +4 flame at the
##            front of the cut, +5 fire arc and heat flash; hits +3 embers, +5 fire blast
##     axe    chop; hits: +1 iron sparks, +2 dust, +3 rune flash and dust; the chop's ground
##            point (hit or miss): +4 dust ring and rubble, +5 a small quake blast
##     bow    the arrow carries +1/+2 a breeze, +3 a wind spiral, +4/+5 electric arcs;
##            impacts +4 arcs, +5 a lightning strike
##     staff  the bolt carries +1 motes, +2 a rune ring at launch, +3 droplets, +4/+5
##            crystal streams; impacts +3 splash, +4 charge burst, +5 warp and light burst
## PlayerAnimator times the courier's swing and release poses to the same moments
## (KayKitCharacter.play_once_strike). Lives in GameplayServices; finds the player.

signal effect_spawned(kind: StringName, effect: Node3D)

const GROUP := &"attack_effects"
const SWING := preload("res://assets/vfx/BinbunVFX_Vol2/BattleFX/effects/swing/vfx_blank_swing.tscn")
## Seconds into the swing's "main" animation (at speed 1) where its arc is fullest.
const SWING_PEAK := 0.25
## The swing plane is 3 m across: its arc radius is 1.5 m at scale 1.
const SWING_RADIUS := 1.5
const SWING_HEIGHT := 0.9
const IMPACT_SIZE := 1.1
## Element colours per weapon class, +1..+5 (fire, earth, wind / lightning, arcane).
const ELEMENT_COLORS := {
	ItemDefinition.WeaponType.SWORD: [Color(0.88, 0.93, 1.0), Color(0.7, 0.88, 1.0), Color(1.0, 0.6, 0.2), Color(1.0, 0.48, 0.15), Color(1.0, 0.42, 0.12)],
	ItemDefinition.WeaponType.AXE: [Color(1.0, 0.85, 0.6), Color(0.85, 0.72, 0.52), Color(1.0, 0.7, 0.25), Color(1.0, 0.62, 0.2), Color(1.0, 0.45, 0.12)],
	ItemDefinition.WeaponType.BOW: [Color(0.85, 1.0, 0.92), Color(0.75, 1.0, 0.9), Color(0.7, 1.0, 0.95), Color(0.55, 0.85, 1.0), Color(0.75, 0.92, 1.0)],
	ItemDefinition.WeaponType.STAFF: [Color(0.82, 0.62, 1.0), Color(0.75, 0.55, 1.0), Color(0.45, 0.78, 1.0), Color(0.72, 0.45, 1.0), Color(0.8, 0.55, 1.0)],
}
const IMPACT_HEIGHT := 0.8
## Metres from a target's centre towards the attacker (about an enemy's radius).
const IMPACT_SURFACE := 0.5

@export var inventory: CourierInventory

var combat: CombatController = null
## The arc of the swing now winding up or sweeping (null when none).
var swing: Node3D = null
## Process-frame time (seconds) the current swing's arc peaks, for tests.
var swing_peak_at: float = -1.0


static func find(tree: SceneTree) -> AttackEffects:
	return tree.get_first_node_in_group(GROUP) as AttackEffects if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _process(_delta: float) -> void:
	if combat != null and is_instance_valid(combat):
		return
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	var player := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP)
	combat = CombatController.find_on(player) if player != null else null
	if combat != null:
		combat.melee_started.connect(_on_melee_started)
		combat.melee_cancelled.connect(_on_melee_cancelled)
		combat.target_hit.connect(_on_target_hit)
		combat.melee_resolved.connect(_on_melee_resolved)
		combat.projectile_launched.connect(_on_projectile_launched)


func _on_melee_started(direction: Vector3, heavy: bool) -> void:
	var body := combat.get_parent() as Node3D
	if body == null:
		return
	_remove_swing()
	var forward := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var color := _weapon_color()
	var arc := _spawn_arc(body, forward, heavy, color, 4.0 if heavy else 3.5, 1.0)
	swing = arc
	swing_peak_at = Time.get_ticks_msec() / 1000.0 + maxf(combat.melee_windup, 0.05)
	effect_spawned.emit(&"swing", arc)
	_melee_elements(body, forward, heavy, arc)


## A BattleFX swing arc round body, sweeping to its fullest when the hit lands.
func _spawn_arc(body: Node3D, forward: Vector3, heavy: bool, color: Color, emission: float, scale: float) -> Node3D:
	var arc := SWING.instantiate() as Node3D
	arc.name = "SwingArc"
	var mesh := arc.get_node(^"Swing") as MeshInstance3D
	# Swings overlap (the sword's cooldown is shorter than the arc): one material each.
	mesh.material_override = mesh.material_override.duplicate()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.set(&"one_shot", true)
	body.add_child(arc)
	var side := forward.cross(Vector3.UP).normalized()
	# The arc is the half-disc on the plane's +X side; its normal is the plane's +Y.
	var basis := Basis(forward, side if heavy else Vector3.UP, forward.cross(side if heavy else Vector3.UP))
	var radius := maxf(combat.melee_range, 0.8) / SWING_RADIUS * scale
	arc.global_basis = basis.orthonormalized().scaled(Vector3.ONE * radius)
	arc.global_position = body.global_position + Vector3.UP * SWING_HEIGHT
	arc.set(&"primary_color", color)
	arc.set(&"secondary_color", color.darkened(0.25))
	arc.set(&"tertiary_color", color.darkened(0.6))
	arc.set(&"emission", emission)
	# Speed so the fullest arc lands on the hit: SWING_PEAK of animation at windup seconds.
	arc.set(&"speed_scale", SWING_PEAK / maxf(combat.melee_windup, 0.05))
	arc.connect(&"finished", arc.queue_free)
	arc.call(&"play")
	return arc


## A one-shot flipbook in the world at a point (it frees itself), reported as kind.
func _spawn_strip(body: Node3D, kind: StringName, source: StringName, size: float, tint: Color, at: Vector3, fps: float = 15.0) -> VfxStrip:
	var root := body.get_parent()
	if root == null:
		return null
	var flash := VfxStrip.create(source, size, tint, false)
	flash.name = "Fx_" + String(kind)
	flash.free_on_finish = true
	flash.fps = fps
	root.add_child(flash)
	flash.global_position = at
	effect_spawned.emit(kind, flash)
	return flash


func _on_melee_cancelled() -> void:
	_remove_swing()


func _remove_swing() -> void:
	if swing != null and is_instance_valid(swing):
		# A +5 swing's fire arc goes with it.
		for sibling in swing.get_parent().get_children():
			if sibling.has_meta(&"swing_owner") and sibling.get_meta(&"swing_owner") == swing:
				sibling.queue_free()
		swing.queue_free()
	swing = null
	swing_peak_at = -1.0


func _on_target_hit(target: Node, _amount: float) -> void:
	# The Magic Bolt has its own burst; melee and arrows flash here.
	if combat.get_attack_style() == CombatController.AttackStyle.MAGIC_BOLT:
		return
	var at := target as Node3D
	var body := combat.get_parent() as Node3D
	if at == null or not at.is_inside_tree() or body == null or body.get_parent() == null:
		return
	var color := _weapon_color()
	var point := impact_point(at, body)
	var flash := VfxStrip.create(&"impact", IMPACT_SIZE, Color(color.lerp(Color.WHITE, 0.35), 0.95), false)
	flash.name = "ImpactFlash"
	flash.free_on_finish = true
	body.get_parent().add_child(flash)
	flash.global_position = point
	effect_spawned.emit(&"impact", flash)
	# An arrow shows its element where it lands (_on_projectile_launched), so only once.
	if weapon_type() != ItemDefinition.WeaponType.BOW:
		_impact_elements(weapon_type(), weapon_tier(), point, body)


## Where a hit on target shows: on its side facing the attacker (not inside its body,
## which would hide the flash), at chest height.
static func impact_point(target: Node3D, attacker: Node3D) -> Vector3:
	var toward := attacker.global_position - target.global_position
	toward.y = 0.0
	var offset := toward.normalized() * minf(IMPACT_SURFACE, toward.length() * 0.5) if toward.length_squared() > 0.0001 else Vector3.ZERO
	return target.global_position + offset + Vector3.UP * IMPACT_HEIGHT


## The enhancement level of the weapon in hand (0 for bare hands or a tool).
func weapon_tier() -> int:
	var item := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) if inventory != null else null
	return inventory.get_enhancement(item.item_id) if item != null and item.is_weapon() else 0


## The weapon class in hand (NONE for bare hands or a tool).
func weapon_type() -> ItemDefinition.WeaponType:
	var item := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) if inventory != null else null
	return item.weapon_type if item != null and item.is_weapon() else ItemDefinition.WeaponType.NONE


## The colour of a weapon class's element at a level (warm white at +0).
static func element_color(type: ItemDefinition.WeaponType, level: int) -> Color:
	if level <= 0:
		return Color(1.0, 0.95, 0.85)
	var palette: Array = ELEMENT_COLORS.get(type, [])
	return palette[clampi(level, 1, 5) - 1] if not palette.is_empty() else Enhancement.level_color(level)


## The weapon's element colour, or a warm white at +0.
func _weapon_color() -> Color:
	return element_color(weapon_type(), weapon_tier())


# --- Phase 8 elemental active effects ----------------------------------------------

func _melee_elements(body: Node3D, forward: Vector3, heavy: bool, arc: Node3D) -> void:
	if weapon_type() != ItemDefinition.WeaponType.SWORD:
		return
	var ahead := body.global_position + forward * 0.9 + Vector3.UP * SWING_HEIGHT
	match weapon_tier():
		2:
			_burst(body, &"sword_ice_streaks", "streak", 10, 0.25, Color(0.75, 0.9, 1.0), ahead, forward, 0.35)
		3:
			_burst(body, &"sword_ember_burst", "dot", 16, 0.1, Color(1.0, 0.55, 0.15), ahead, forward, 0.6)
		4:
			_spawn_strip(body, &"sword_flame_front", &"flame", 0.9, Color.WHITE, ahead)
			_burst(body, &"sword_ember_burst", "dot", 18, 0.1, Color(1.0, 0.55, 0.15), ahead, forward, 0.6)
		5:
			var fire := _spawn_arc(body, forward, heavy, Color(1.0, 0.42, 0.12), 6.0, 1.18)
			fire.name = "LegendaryArc"
			fire.set_meta(&"swing_owner", arc)
			effect_spawned.emit(&"legendary_trail", fire)
			_spawn_strip(body, &"sword_heat_flash", &"slash_flash", 1.4, Color(1.0, 0.6, 0.2, 1.0), ahead)
			_spawn_strip(body, &"sword_flame_front", &"flame_b", 1.0, Color.WHITE, ahead)


func _impact_elements(type: ItemDefinition.WeaponType, level: int, point: Vector3, body: Node3D) -> void:
	if level <= 0:
		return
	match type:
		ItemDefinition.WeaponType.SWORD:
			if level >= 3:
				_burst(body, &"sword_ember_impact", "dot", 12, 0.09, Color(1.0, 0.6, 0.2), point, Vector3.UP, 0.5)
			if level == 5:
				_spawn_strip(body, &"sword_fire_impact", &"blast", 1.5, Color.WHITE, point)
		ItemDefinition.WeaponType.AXE:
			match level:
				1:
					_spawn_strip(body, &"axe_iron_sparks", &"spark", 1.0, Color(1.0, 0.82, 0.55), point)
				2:
					_spawn_strip(body, &"axe_dust", &"dust_puff", 1.2, Color(0.8, 0.68, 0.52, 0.95), point)
				_:
					_spawn_strip(body, &"axe_rune_flash", &"warp", 1.4, Color(1.0, 0.68, 0.22, 1.0), point)
					_spawn_strip(body, &"axe_dust", &"dust_puff", 1.3, Color(0.8, 0.68, 0.52, 0.95), point)
		ItemDefinition.WeaponType.BOW:
			if level >= 4:
				_spawn_strip(body, &"bow_arc_impact", &"arc_ring", 1.4, Color(0.6, 0.88, 1.0, 1.0), point)
			if level == 5:
				_spawn_strip(body, &"bow_lightning_impact", &"strike", 1.8, Color.WHITE, point + Vector3.UP * 0.5)
		ItemDefinition.WeaponType.STAFF:
			match level:
				3:
					_spawn_strip(body, &"staff_splash", &"splash", 1.3, Color(0.45, 0.8, 1.0, 0.95), point)
				4:
					_spawn_strip(body, &"staff_charge_burst", &"charge", 1.3, Color(0.8, 0.6, 1.0, 1.0), point)
				5:
					_spawn_strip(body, &"staff_warp_impact", &"warp", 1.8, Color(0.8, 0.6, 1.0, 1.0), point)
					_spawn_strip(body, &"staff_light_burst", &"light_burst", 1.6, Color(0.85, 0.75, 1.0, 1.0), point)


## The axe's chop marks the ground in front of the courier at +4 and +5 (hit or miss).
func _on_melee_resolved(_hits: int) -> void:
	var level := weapon_tier()
	if weapon_type() != ItemDefinition.WeaponType.AXE or level < 4:
		return
	var body := combat.get_parent() as Node3D
	if body == null or body.get_parent() == null:
		return
	var aim := combat.get_aim_direction()
	var ground := body.global_position + aim * maxf(combat.melee_range * 0.8, 0.8) + Vector3.UP * 0.25
	_spawn_strip(body, &"axe_ground_ring", &"dust_ring", 2.0 if level == 5 else 1.5, Color.WHITE, ground)
	_spawn_strip(body, &"axe_rubble", &"rubble", 1.3, Color(0.75, 0.66, 0.52, 0.95), ground + Vector3.UP * 0.2)
	if level == 5:
		_spawn_strip(body, &"axe_quake_blast", &"quake_blast", 1.6, Color.WHITE, ground + Vector3.UP * 0.4)


## Arrows and bolts carry their weapon's element (children of the projectile, freed with it).
func _on_projectile_launched(projectile: CombatProjectile, _kind: StringName) -> void:
	var level := weapon_tier()
	var type := weapon_type()
	if level <= 0 or not (type in [ItemDefinition.WeaponType.BOW, ItemDefinition.WeaponType.STAFF]):
		return
	var body := combat.get_parent() as Node3D
	# Bow hits are also reported by target_hit (that adds only the generic flash); the
	# element of an arrow or bolt hit shows here, once per projectile.
	projectile.hit.connect(func(target: Node, _amount: float) -> void:
		var at := target as Node3D
		if at != null and is_instance_valid(at) and at.is_inside_tree() and is_instance_valid(body):
			_impact_elements(type, level, impact_point(at, body), body))
	var trail: CPUParticles3D = null
	if type == ItemDefinition.WeaponType.BOW:
		match level:
			1, 2:
				trail = _trail(projectile, &"bow_breeze_trail", "streak", 10, 0.2, Color(0.85, 1.0, 0.92))
			3:
				trail = _trail(projectile, &"bow_wind_spiral", "streak", 14, 0.22, Color(0.8, 1.0, 0.92))
				_spiral(projectile, Color(0.8, 1.0, 0.92, 0.95))
			_:
				trail = _trail(projectile, &"bow_charged_arrow", "dot", 18, 0.08, Color(0.7, 0.9, 1.0))
				_spiral(projectile, Color(0.8, 1.0, 0.95, 0.9))
				var arcs := VfxStrip.create(&"arc_ring", 0.7 if level == 4 else 0.95, Color(0.65, 0.9, 1.0, 1.0), true)
				arcs.name = "ChargedArcs"
				projectile.add_child(arcs)
	else:
		match level:
			1:
				trail = _trail(projectile, &"staff_mote_trail", "dot", 12, 0.08, Color(0.82, 0.62, 1.0))
			2:
				trail = _trail(projectile, &"staff_mote_trail", "dot", 12, 0.08, Color(0.82, 0.62, 1.0))
				_spawn_strip(body, &"staff_launch_rune", &"warp", 1.0, Color(0.8, 0.6, 1.0, 1.0), projectile.global_position)
			3:
				trail = _trail(projectile, &"staff_droplet_trail", "dot", 16, 0.09, Color(0.45, 0.8, 1.0))
			_:
				trail = _trail(projectile, &"staff_crystal_stream", "streak", 20, 0.2, Color(0.8, 0.6, 1.0))
	if trail != null:
		effect_spawned.emit(StringName(trail.name), trail)


## World-space particles left behind a projectile.
func _trail(projectile: Node3D, kind: StringName, texture: String, amount: int, size: float, color: Color) -> CPUParticles3D:
	var emitter := _particle_emitter(texture, amount, size, color, 0.45)
	emitter.name = String(kind)
	emitter.initial_velocity_max = 0.3
	projectile.add_child(emitter)
	return emitter


## Three wind streaks turning round a projectile.
func _spiral(projectile: Node3D, color: Color) -> void:
	var pivot := Node3D.new()
	pivot.name = "WindSpiral"
	projectile.add_child(pivot)
	var texture := EnhancementGlow._texture("streak")
	for i in 3:
		var streak := Sprite3D.new()
		streak.texture = texture
		streak.pixel_size = 0.4 / 32.0
		streak.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		streak.material_override = EnhancementGlow._additive(texture, color)
		streak.position = Vector3(cos(TAU * i / 3.0), sin(TAU * i / 3.0), 0.0) * 0.25
		pivot.add_child(streak)
	var tween := pivot.create_tween().set_loops()
	tween.tween_property(pivot, ^"rotation:z", TAU, 0.35).from(0.0)


## A one-shot burst of particles at a point (frees itself).
func _burst(body: Node3D, kind: StringName, texture: String, amount: int, size: float, color: Color, at: Vector3, direction: Vector3, lifetime: float) -> void:
	var root := body.get_parent()
	if root == null:
		return
	var emitter := _particle_emitter(texture, amount, size, color, lifetime)
	emitter.name = "Fx_" + String(kind)
	emitter.one_shot = true
	emitter.explosiveness = 0.9
	emitter.direction = direction
	emitter.spread = 50.0
	emitter.initial_velocity_min = 1.0
	emitter.initial_velocity_max = 2.4
	root.add_child(emitter)
	emitter.global_position = at
	emitter.emitting = true
	emitter.finished.connect(emitter.queue_free)
	effect_spawned.emit(kind, emitter)


func _particle_emitter(texture: String, amount: int, size: float, color: Color, lifetime: float) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.gravity = Vector3.ZERO
	emitter.spread = 180.0
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 1.0))
	fade.set_color(1, Color(color, 0.0))
	emitter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := EnhancementGlow._additive(EnhancementGlow._texture(texture), Color.WHITE)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	emitter.mesh = quad
	return emitter
