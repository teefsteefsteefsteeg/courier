@tool
class_name Cottage
extends StaticBody3D
## Reusable PLACEHOLDER cottage. Wall and roof colours are per-instance so one
## scene can dress the whole village. Runs in the editor so recolours show live.

@export var wall_color: Color = Color(0.93, 0.88, 0.76):
	set(value):
		wall_color = value
		_apply_colors()
@export var roof_color: Color = Color(0.72, 0.27, 0.2):
	set(value):
		roof_color = value
		_apply_colors()


func _ready() -> void:
	_apply_colors()


func _apply_colors() -> void:
	if not is_inside_tree():
		return
	_tint(get_node_or_null(^"Walls") as MeshInstance3D, wall_color)
	_tint(get_node_or_null(^"Roof") as MeshInstance3D, roof_color)


static func _tint(mesh: MeshInstance3D, color: Color) -> void:
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
