class_name FacingComponent
extends Node
## Smoothly rotates a visual node around Y so its local -Z faces a world direction.
## Rotating only the visual keeps the physics body's collision shape unaffected.

@export var visual_root: Node3D
## Higher values turn faster. Frame-rate independent (exponential smoothing).
@export_range(1.0, 50.0, 0.5) var turn_sharpness: float = 14.0


func update_facing(direction: Vector3, delta: float) -> void:
	if visual_root == null:
		return
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() < 0.0001:
		return
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, yaw_for_direction(direction), 1.0 - exp(-turn_sharpness * delta))


## Yaw (radians) that makes local -Z point along the given world direction.
static func yaw_for_direction(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## World-space forward direction of the visual (flattened to XZ).
func get_facing_direction() -> Vector3:
	if visual_root == null:
		return Vector3.FORWARD
	var forward := -visual_root.global_basis.z
	forward.y = 0.0
	return forward.normalized()
