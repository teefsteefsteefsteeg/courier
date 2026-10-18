class_name Spinner
extends Node3D
## Turns this node steadily around one of its local axes (the mill's sails).

@export var axis := Vector3.BACK
@export_range(-360.0, 360.0, 1.0, "suffix:°/s") var degrees_per_second: float = 18.0


func _process(delta: float) -> void:
	rotate_object_local(axis.normalized(), deg_to_rad(degrees_per_second) * delta)
