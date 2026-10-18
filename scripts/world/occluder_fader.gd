class_name OccluderFader
extends Node
## Each frame, tells every CameraOccluder whether it stands between the camera
## and the target (the player), so trees and roofs fade instead of hiding them.

@export var camera_rig: IsoCameraRig
@export var target: Node3D
## Heights above the target's origin that are tested (feet-ish and head).
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.4, 1.6])


func _process(_delta: float) -> void:
	if camera_rig == null or target == null:
		return
	# The rig's rotation is fixed, so its +Z is the unit direction towards the camera.
	var to_camera := camera_rig.camera.global_basis.z.normalized()
	var base := target.get_global_transform_interpolated().origin
	for node in get_tree().get_nodes_in_group(CameraOccluder.GROUP):
		var occluder := node as CameraOccluder
		var blocked := false
		for h in sample_heights:
			if occluder.blocks_ray(base + Vector3.UP * h, to_camera):
				blocked = true
				break
		occluder.set_occluding(blocked)
