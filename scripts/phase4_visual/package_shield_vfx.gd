extends Node3D
## Package shield visual: a faceted translucent bubble around the carried
## package with a rotating rune ring. Colour and opacity track durability
## (teal when full, ember orange when nearly broken); losing durability flashes
## the bubble, deactivating collapses it. Purely visual.
##
## set_shield(active, durability): durability is a 0..1 ratio. Values above 1
## are treated as raw points and divided by durability_scale (default 100).

signal shield_visibility_changed(shown: bool)

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const FULL_COLOR := Color(0.4, 0.95, 0.85)
const LOW_COLOR := Color(1.0, 0.45, 0.2)

@export var auto_animate := true
@export var radius := 0.75
@export var durability_scale := 100.0
@export var collapse_duration := 0.25
@export var follow_offset := Vector3(0, 0.9, 0)

var follow_target: Node3D
var active := false
var durability := 1.0
var crack_flash := 0.0
var bubble: MeshInstance3D
var rune_ring: MeshInstance3D
var bubble_material: StandardMaterial3D
var ring_material: StandardMaterial3D

var _presence := 0.0  ## 0 hidden .. 1 fully raised
var _time := 0.0


func _ready() -> void:
	_ensure_built()
	_apply()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


func set_shield(p_active: bool, p_durability: float) -> void:
	_ensure_built()
	var ratio := p_durability
	if ratio > 1.0:
		ratio /= maxf(durability_scale, 0.001)
	ratio = clampf(ratio, 0.0, 1.0)
	if p_active and active and ratio < durability - 0.001:
		crack_flash = 1.0
	var was_shown := is_shown()
	active = p_active
	durability = ratio
	if active and not was_shown:
		visible = true
		shield_visibility_changed.emit(true)
	_apply()


func advance(delta: float) -> void:
	_time += delta
	var rate := delta / maxf(collapse_duration, 0.001)
	_presence = minf(1.0, _presence + rate) if active else maxf(0.0, _presence - rate)
	crack_flash = maxf(0.0, crack_flash - delta * 4.0)
	if follow_target != null and is_instance_valid(follow_target) and follow_target.is_inside_tree() and is_inside_tree():
		global_position = follow_target.global_position + follow_offset
	if not active and _presence <= 0.0 and visible:
		visible = false
		shield_visibility_changed.emit(false)
	_apply()


func is_shown() -> bool:
	return visible and (active or _presence > 0.0)


func get_presence() -> float:
	return _presence


func get_current_color() -> Color:
	return bubble_material.albedo_color


func _apply() -> void:
	if bubble == null:
		return
	var base := LOW_COLOR.lerp(FULL_COLOR, durability)
	var c := base.lerp(Color.WHITE, crack_flash * 0.6)
	c.a = lerpf(0.12, 0.38, durability) * _presence + crack_flash * 0.3
	bubble_material.albedo_color = c
	bubble_material.emission = base
	var pulse := 1.0 + sin(_time * 4.0) * 0.03 + crack_flash * 0.08
	bubble.scale = Vector3.ONE * maxf(0.001, _presence * pulse)
	var rc := base
	rc.a = 0.8 * _presence
	ring_material.albedo_color = rc
	rune_ring.scale = Vector3.ONE * maxf(0.001, _presence)
	rune_ring.rotation = Vector3(0.25, _time * 1.8, 0.0)


func _ensure_built() -> void:
	if bubble != null:
		return
	bubble_material = Lowpoly.load_material("package_shield.tres", Color(0.4, 0.95, 0.85, 0.3))
	bubble = Lowpoly.add_part(self, "Bubble", Lowpoly.sphere(radius, radius * 2.0, 10, 5), bubble_material, Vector3.ZERO, false)
	ring_material = Lowpoly.make_material(Color(0.4, 0.95, 0.85, 0.8), 1.5, true)
	ring_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rune_ring = Lowpoly.add_part(self, "RuneRing", Lowpoly.ring(radius * 0.95, radius * 1.05, 12), ring_material, Vector3.ZERO, false)
	visible = false
