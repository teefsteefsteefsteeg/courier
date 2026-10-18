class_name MergedProp
extends StaticBody3D
## A prop assembled from several model pieces under `Model` (an armory weapon
## rack, a display table). The pieces are merged at runtime into one mesh per
## material, like MedievalBuilding, so a rack of swords is one or two draw calls.


func _ready() -> void:
	var model := get_node_or_null(^"Model") as Node3D
	if model != null:
		MedievalBuilding.merge_pieces(model, scene_file_path + ":Model" if not scene_file_path.is_empty() else "")
