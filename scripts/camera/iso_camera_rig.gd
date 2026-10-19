class_name IsoCameraRig
extends Node3D
## Fixed-angle orthographic isometric camera. The rig smoothly follows a target;
## its rotation never changes at runtime, so camera-relative input stays stable.
## add_shake() (Phase 8 skill impacts, GroundFx.shake) jitters the camera's screen offset
## only, so the rig's position and input directions are untouched.

const GROUP := &"iso_camera_rig"

@export var target: Node3D

@export_group("Angle")
@export_range(0.0, 360.0, 0.5, "degrees") var yaw_degrees: float = 45.0
@export_range(10.0, 80.0, 0.5, "degrees") var pitch_degrees: float = 35.0
## Distance from the focus point along the view axis (affects clipping only in orthographic).
@export_range(5.0, 200.0, 0.5, "suffix:m") var distance: float = 40.0
## Offset from the target origin that the camera centers on.
@export var focus_offset: Vector3 = Vector3(0.0, 0.8, 0.0)

@export_group("Follow")
## Higher values follow more tightly. Frame-rate independent.
@export_range(0.5, 40.0, 0.5) var follow_sharpness: float = 7.0

@export_group("Zoom")
## Orthographic size: vertical world height visible on screen, in meters.
@export_range(2.0, 60.0, 0.5, "suffix:m") var zoom_size: float = 14.0
@export_range(2.0, 60.0, 0.5, "suffix:m") var min_zoom_size: float = 8.0
@export_range(2.0, 60.0, 0.5, "suffix:m") var max_zoom_size: float = 22.0
@export_range(0.1, 10.0, 0.1, "suffix:m") var zoom_step: float = 1.5
@export_range(0.5, 40.0, 0.5) var zoom_sharpness: float = 10.0

@onready var camera: Camera3D = $Camera3D

var target_zoom_size: float
var _shake_strength: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _shake_rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# The rig is moved in _process from the target's interpolated transform,
	# so engine-side physics interpolation must not also smooth it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	rotation_degrees = Vector3(-pitch_degrees, yaw_degrees, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
	camera.rotation = Vector3.ZERO
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = distance * 2.0 + 50.0
	target_zoom_size = clampf(zoom_size, min_zoom_size, max_zoom_size)
	camera.size = target_zoom_size
	snap_to_target()


func _process(delta: float) -> void:
	if target != null:
		global_position = global_position.lerp(_focus_point(), 1.0 - exp(-follow_sharpness * delta))
	camera.size = lerpf(camera.size, target_zoom_size, 1.0 - exp(-zoom_sharpness * delta))
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		var amount := _shake_strength * (_shake_left / maxf(_shake_total, 0.001))
		camera.h_offset = _shake_rng.randf_range(-amount, amount)
		camera.v_offset = _shake_rng.randf_range(-amount, amount)
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Shakes the view by up to strength metres, easing out over seconds. A stronger or longer
## shake wins over the one running.
func add_shake(strength: float, seconds: float) -> void:
	if strength >= _shake_strength * (_shake_left / maxf(_shake_total, 0.001)):
		_shake_strength = strength
		_shake_left = seconds
		_shake_total = seconds


func get_shake_remaining() -> float:
	return _shake_left


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"zoom_in"):
		set_zoom(target_zoom_size - zoom_step)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"zoom_out"):
		set_zoom(target_zoom_size + zoom_step)
		get_viewport().set_input_as_handled()


func set_zoom(size: float) -> void:
	target_zoom_size = clampf(size, min_zoom_size, max_zoom_size)


func snap_to_target() -> void:
	if target != null:
		global_position = _focus_point()


func _focus_point() -> Vector3:
	return target.get_global_transform_interpolated().origin + focus_offset
