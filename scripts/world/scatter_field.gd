class_name ScatterField
extends MultiMeshInstance3D
## Draws many copies of one imported model (grass tufts, flowers, ferns) as a
## single MultiMesh. Placements are baked into `transforms`; the source model's
## internal node transform is applied on top of each placement.

@export var source: PackedScene
@export var transforms: Array[Transform3D] = []
## Optional material name -> albedo colour, e.g. to make yellow or pink flowers.
@export var colors: Dictionary = {}


func _ready() -> void:
	if source == null or transforms.is_empty():
		return
	var model := source.instantiate() as Node3D
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		model.free()
		return
	var mesh_node := meshes[0] as MeshInstance3D
	var local := Transform3D.IDENTITY
	var node: Node = mesh_node
	while node != model:
		local = (node as Node3D).transform * local
		node = node.get_parent()
	var mesh := mesh_node.mesh
	if not colors.is_empty():
		mesh = mesh.duplicate()
		for surface in mesh.get_surface_count():
			var source_material := mesh.surface_get_material(surface) as BaseMaterial3D
			if source_material != null and colors.has(source_material.resource_name):
				mesh.surface_set_material(surface, ModelTint.tinted(source_material, colors[source_material.resource_name], null, 0.0))
	model.free()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i] * local)
	multimesh = multi
