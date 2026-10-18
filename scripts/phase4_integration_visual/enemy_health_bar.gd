extends Node3D
## Floating enemy health bar for the Phase 4 integration encounter. Follows its
## enemy, faces the active camera, trails a pale "recent damage" chunk behind
## the fill, flashes and shakes on hit and fades out on death. Purely visual:
## values are pushed in by the encounter presentation.
## Animation runs from _process, or manually via advance(delta) when
## auto_animate is false (deterministic tests).

signal faded

const Assets := preload("res://scripts/phase4_integration_visual/integration_assets.gd")
const FULL_COLOR := Color(0.45, 0.95, 0.35)
const MID_COLOR := Color(1.0, 0.85, 0.25)
const LOW_COLOR := Color(1.0, 0.3, 0.22)
const LAG_COLOR := Color(1.0, 0.95, 0.8, 0.9)
const BACK_COLOR := Color(0.05, 0.07, 0.06, 0.85)
const BACK_HIT_COLOR := Color(0.6, 0.1, 0.08, 0.9)

@export var auto_animate := true
@export var width := 0.9
@export var height := 0.11
@export var follow_offset := Vector3(0, 1.4, 0)
## Seconds the damage chunk holds before draining.
@export var lag_delay := 0.25
## Ratio per second the damage chunk drains.
@export var lag_speed := 1.2
@export var fade_duration := 0.5
@export var face_camera := true

var follow_target: Node3D
## Kind colour pip at the left edge (slime green, wisp blue).
var accent := Color(0.6, 1.0, 0.5)
var current := 1.0
var maximum := 1.0
var ratio := 1.0
var lag_ratio := 1.0
var flash := 0.0
var shake := 0.0
var dying := false
var presence := 1.0  ## 1 shown .. 0 faded out
var back_mesh: MeshInstance3D
var lag_mesh: MeshInstance3D
var fill_mesh: MeshInstance3D
var accent_mesh: MeshInstance3D
var back_material: StandardMaterial3D
var lag_material: StandardMaterial3D
var fill_material: StandardMaterial3D
var accent_material: StandardMaterial3D

var _lag_hold := 0.0
var _time := 0.0
var _faded_emitted := false


func _ready() -> void:
	_ensure_built()
	_follow()
	_apply()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


func set_health(p_current: float, p_maximum: float) -> void:
	_ensure_built()
	maximum = maxf(p_maximum, 0.001)
	var next := clampf(p_current, 0.0, maximum)
	if next < current:
		_lag_hold = lag_delay
	current = next
	ratio = current / maximum
	if ratio > lag_ratio:
		lag_ratio = ratio
	_apply()


func apply_damage(amount: float) -> void:
	set_health(current - amount, maximum)


func play_hit() -> void:
	if dying:
		return
	flash = 1.0
	shake = 1.0
	_apply()


func play_death() -> void:
	if dying:
		return
	dying = true
	flash = 1.0
	set_health(0.0, maximum)


func reset_bar() -> void:
	dying = false
	presence = 1.0
	visible = true
	flash = 0.0
	shake = 0.0
	_faded_emitted = false
	current = maximum
	ratio = 1.0
	lag_ratio = 1.0
	_lag_hold = 0.0
	_apply()


func advance(delta: float) -> void:
	_time += delta
	flash = maxf(0.0, flash - delta * 4.0)
	shake = maxf(0.0, shake - delta * 3.5)
	if _lag_hold > 0.0:
		_lag_hold -= delta
	elif lag_ratio > ratio:
		lag_ratio = maxf(ratio, lag_ratio - lag_speed * delta)
	if dying and presence > 0.0:
		presence = maxf(0.0, presence - delta / maxf(fade_duration, 0.001))
		if presence <= 0.0 and not _faded_emitted:
			_faded_emitted = true
			visible = false
			faded.emit()
	_follow()
	_apply()


func is_faded() -> bool:
	return _faded_emitted


func get_fill_color() -> Color:
	_ensure_built()
	return fill_material.albedo_color


static func health_color(r: float) -> Color:
	if r >= 0.5:
		return MID_COLOR.lerp(FULL_COLOR, (r - 0.5) * 2.0)
	return LOW_COLOR.lerp(MID_COLOR, maxf(r, 0.0) * 2.0)


# --- internals -----------------------------------------------------------------

func _follow() -> void:
	if not is_inside_tree():
		return
	if follow_target != null and is_instance_valid(follow_target) and follow_target.is_inside_tree():
		global_position = follow_target.global_position + follow_offset
	if face_camera:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			global_basis = cam.global_basis


func _apply() -> void:
	if fill_mesh == null:
		return
	var sx := sin(_time * 70.0) * 0.05 * shake
	_place(fill_mesh, ratio, sx, 0.004)
	_place(lag_mesh, lag_ratio, sx, 0.002)
	back_mesh.position = Vector3(sx, 0.0, 0.0)
	accent_mesh.position = Vector3(sx - width * 0.5 - 0.07, 0.0, 0.004)

	var fc := health_color(ratio).lerp(Color.WHITE, flash * 0.7)
	fc.a = presence
	fill_material.albedo_color = fc
	var lc := LAG_COLOR
	lc.a *= presence
	lag_material.albedo_color = lc
	var bc := BACK_COLOR.lerp(BACK_HIT_COLOR, flash * 0.5)
	bc.a *= presence
	back_material.albedo_color = bc
	var ac := accent
	ac.a = presence
	accent_material.albedo_color = ac
	scale = Vector3.ONE * (1.0 + flash * 0.12)


func _place(mesh: MeshInstance3D, r: float, sx: float, z: float) -> void:
	var rr := maxf(r, 0.0001)
	mesh.scale = Vector3(rr, 1.0, 1.0)
	mesh.position = Vector3(sx - width * (1.0 - rr) * 0.5, 0.0, z)
	mesh.visible = r > 0.0005


func _ensure_built() -> void:
	if fill_mesh != null:
		return
	back_material = Assets.make_overlay(Assets.load_material("enemy_health_back.tres", BACK_COLOR), 10)
	lag_material = Assets.make_overlay(Assets.load_material("enemy_health_lag.tres", LAG_COLOR), 11)
	fill_material = Assets.make_overlay(Assets.load_material("enemy_health_fill.tres", FULL_COLOR), 12)
	accent_material = Assets.make_overlay(Assets.load_material("enemy_health_fill.tres", accent), 12)
	back_mesh = _quad("Back", Vector2(width + 0.05, height + 0.05), back_material)
	lag_mesh = _quad("Lag", Vector2(width, height), lag_material)
	fill_mesh = _quad("Fill", Vector2(width, height), fill_material)
	accent_mesh = _quad("KindPip", Vector2(0.08, height + 0.05), accent_material)


func _quad(part_name: String, size: Vector2, mat: Material) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
