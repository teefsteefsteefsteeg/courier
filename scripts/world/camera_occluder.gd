class_name CameraOccluder
extends Node3D
## Marks its parent (a tree, a cottage) as something that can hide the player
## from the fixed isometric camera. While an OccluderFader reports that the
## player is behind it, every GeometryInstance3D under the parent fades.
##
## The occluding volume is a vertical segment from this node's origin up
## `height`, thickened by `radius`. Both scale with the node's global scale.

const GROUP := &"camera_occluder"

@export_range(0.1, 10.0, 0.05, "suffix:m") var radius: float = 1.4
@export_range(0.1, 20.0, 0.05, "suffix:m") var height: float = 3.8
## GeometryInstance3D.transparency applied when fully faded (0 = opaque, 1 = invisible).
@export_range(0.0, 1.0, 0.05) var faded_transparency: float = 0.7
## Fade amount change per second.
@export_range(0.5, 30.0, 0.5) var fade_speed: float = 6.0

var occluding: bool = false
var _geometry: Array[GeometryInstance3D] = []
var _amount: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	collect_geometry()
	set_process(false)


## Finds the geometry to fade. Call again if the parent's meshes are replaced
## (MedievalBuilding merges its pieces after this node is ready).
func collect_geometry() -> void:
	_geometry.clear()
	var stack: Array[Node] = [get_parent()]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D and not node.is_queued_for_deletion():
			_geometry.append(node)
		stack.append_array(node.get_children())


func set_occluding(value: bool) -> void:
	if value == occluding:
		return
	occluding = value
	set_process(true)


func get_fade_amount() -> float:
	return _amount


func _process(delta: float) -> void:
	var target := 1.0 if occluding else 0.0
	_amount = move_toward(_amount, target, fade_speed * delta)
	for geometry in _geometry:
		geometry.transparency = _amount * faded_transparency
	if is_equal_approx(_amount, target):
		set_process(false)


## True if the ray from `origin` along unit `direction` (towards the camera)
## passes through this occluder's volume in front of the origin.
func blocks_ray(origin: Vector3, direction: Vector3) -> bool:
	var base := global_position
	var w0 := origin - base
	var b := direction.y  # direction · up
	var along_ray := direction.dot(w0)
	var denom := 1.0 - b * b
	# Closest points between the ray and the vertical segment base + up * s.
	var s := clampf((w0.y - b * along_ray) / denom, 0.0, height * global_basis.y.length()) if denom > 0.0001 else 0.0
	var t := s * b - along_ray
	if t <= 0.0:
		return false
	return (origin + direction * t).distance_to(base + Vector3.UP * s) < radius * global_basis.x.length()
