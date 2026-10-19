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


func _on_melee_started(direction: Vector3, heavy: bool) -> void:
	var body := combat.get_parent() as Node3D
	if body == null:
		return
	_remove_swing()
	var forward := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var tier := weapon_tier()
	var color := _weapon_color()
	var arc := _spawn_arc(body, forward, heavy, color, 4.0 if heavy else 3.5, 1.0)
	swing = arc
	swing_peak_at = Time.get_ticks_msec() / 1000.0 + maxf(combat.melee_windup, 0.05)
	effect_spawned.emit(&"swing", arc)
	# Phase 8 tier trails, on top of the arc in the weapon's colour.
	var ahead := body.global_position + forward * 0.9 + Vector3.UP * SWING_HEIGHT
	match tier:
		3:
			_spawn_strip(body, &"water_trail", &"bubbles", 0.9, Color(0.6, 0.88, 1.0, 0.9), ahead, 36.0)
		4:
			_spawn_strip(body, &"lightning_flash", &"bolt_flash", 0.9, Color.WHITE, ahead)
		5:
			var fire := _spawn_arc(body, forward, heavy, Color(1.0, 0.42, 0.12), 6.0, 1.18)
			fire.name = "LegendaryArc"
			fire.set_meta(&"swing_owner", arc)
			effect_spawned.emit(&"legendary_trail", fire)
			_spawn_strip(body, &"lightning_flash", &"bolt_flash", 0.8, Color.WHITE, ahead)


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
	# Phase 8 elemental impacts by tier: a splash, an electric strike, a legendary blast.
	match weapon_tier():
		3:
			_spawn_strip(body, &"water_splash", &"splash", 1.3, Color(0.45, 0.8, 1.0, 0.95), point)
		4:
			_spawn_strip(body, &"electric_impact", &"strike", 1.5, Color.WHITE, point + Vector3.UP * 0.3)
		5:
			_spawn_strip(body, &"legendary_blast", &"blast", 1.6, Color.WHITE, point)
			_spawn_strip(body, &"electric_impact", &"strike", 1.2, Color.WHITE, point + Vector3.UP * 0.3)


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


## The weapon's enhancement colour, or a warm white at +0.
func _weapon_color() -> Color:
	var level := weapon_tier()
	return Enhancement.level_color(level) if level > 0 else Color(1.0, 0.95, 0.85)
