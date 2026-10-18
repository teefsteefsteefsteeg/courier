class_name MedievalBuilding
extends StaticBody3D
## A village building with per-instance colours, so one palette of shared
## materials can dress every home (and the purple-roofed alchemy shop).
## Transparent colours keep the model's own material.
##
## Phase 5F buildings are assembled from many Medieval Village MegaKit pieces
## under `Model` (and a turning `Sails` node on the mill). With `merge_model`
## those pieces are combined at runtime into one mesh per material, so a
## building costs a handful of draw calls instead of one per piece and surface.

const ROOF_MATERIALS := ["RoofTiles", "RoofTiles_Red"]
const WALL_MATERIALS := ["Plaster", "Beige"]
const WINDOW_MATERIALS := ["Windows"]
## Children whose pieces are merged when `merge_model` is on.
const MERGED_NODES := [^"Model", ^"Sails"]

@export var roof_color := Color(0, 0, 0, 0)
@export var wall_color := Color(0, 0, 0, 0)
## Emission for window panes (lit interiors). Transparent = unlit.
@export var window_glow := Color(0, 0, 0, 0)
@export_range(0.0, 8.0, 0.1) var window_glow_energy: float = 0.6
## Combine the modular pieces into one mesh per material (see class doc).
@export var merge_model := false

## Merged meshes by scene path and node, shared by every instance of a scene.
static var _merged: Dictionary = {}


func _ready() -> void:
	if merge_model:
		for path in MERGED_NODES:
			var node := get_node_or_null(path) as Node3D
			if node != null:
				merge_pieces(node, "%s:%s" % [scene_file_path, path] if not scene_file_path.is_empty() else "")
		var occluder := get_node_or_null(^"CameraOccluder") as CameraOccluder
		if occluder != null:
			occluder.collect_geometry()
	var colors := {}
	for key in ROOF_MATERIALS:
		if roof_color.a > 0.0:
			colors[key] = roof_color
	for key in WALL_MATERIALS:
		if wall_color.a > 0.0:
			colors[key] = wall_color
	var glow := {}
	for key in WINDOW_MATERIALS:
		if window_glow.a > 0.0:
			glow[key] = window_glow
	ModelTint.apply(self, colors, glow, window_glow_energy)


## Replaces every mesh under `node` with a single child MeshInstance3D named
## "Merged" that draws the same geometry, one surface per material. `cache_key`
## (empty = no caching) lets later instances reuse the mesh.
static func merge_pieces(node: Node3D, cache_key: String) -> void:
	var mesh: ArrayMesh = _merged.get(cache_key) if not cache_key.is_empty() else null
	if mesh == null:
		mesh = merged_mesh(node)
		if not cache_key.is_empty():
			_merged[cache_key] = mesh
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
	var merged := MeshInstance3D.new()
	merged.name = "Merged"
	merged.mesh = mesh
	node.add_child(merged)


## Geometry of every visible mesh under `node`, in `node`'s space, grouped by material.
static func merged_mesh(node: Node3D) -> ArrayMesh:
	var tools := {}
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var piece := child as MeshInstance3D
		if piece.mesh == null or not piece.visible:
			continue
		var local := Transform3D.IDENTITY
		var walk: Node = piece
		while walk != node:
			local = (walk as Node3D).transform * local
			walk = walk.get_parent()
		for surface in piece.mesh.get_surface_count():
			var material := piece.get_active_material(surface)
			if not tools.has(material):
				tools[material] = SurfaceTool.new()
			(tools[material] as SurfaceTool).append_from(piece.mesh, surface, local)
	var mesh := ArrayMesh.new()
	for material in tools:
		var tool := tools[material] as SurfaceTool
		tool.set_material(material)
		tool.commit(mesh)
	return mesh
