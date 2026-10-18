class_name OccluderFader
extends Node
## Each frame, tells every CameraOccluder whether it stands between the camera
## and the target (the player), so trees and roofs fade instead of hiding them.

@export var camera_rig: IsoCameraRig
@export var target: Node3D
## Heights above the target's origin that are tested (feet-ish and head).
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.4, 1.6])
## Post-office walls and furniture were missing CameraOccluder components.
@export var interior_root: Node3D
var _interior_meshes: Array[MeshInstance3D] = []
var _player_indicator: Label3D


func _ready() -> void:
	if interior_root != null:
		for node in interior_root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh != null and mesh.get_aabb().size.y > 0.3:
				_interior_meshes.append(mesh)
	if target != null:
		_player_indicator = Label3D.new()
		_player_indicator.name = "CourierVisibilityMarker"
		_player_indicator.text = "YOU"
		_player_indicator.position.y = 2.8
		_player_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_player_indicator.no_depth_test = true
		_player_indicator.modulate = Color(0.35, 0.8, 1.0)
		_player_indicator.font_size = 24
		_player_indicator.pixel_size = 0.008
		target.add_child(_player_indicator)


func _process(_delta: float) -> void:
	if camera_rig == null or target == null:
		return
	# The rig's rotation is fixed, so its +Z is the unit direction towards the camera.
	var to_camera := camera_rig.camera.global_basis.z.normalized()
	var base := target.get_global_transform_interpolated().origin
	var any_blocked := false
	for mesh in _interior_meshes:
		var inverse := mesh.global_transform.affine_inverse()
		var blocked := false
		for h in sample_heights:
			var origin := base + Vector3.UP * h
			if mesh.get_aabb().intersects_segment(inverse * origin, inverse * (origin + to_camera * camera_rig.distance)) != null:
				blocked = true
				break
		mesh.transparency = move_toward(mesh.transparency, 0.88 if blocked else 0.0, _delta * 6.0)
		any_blocked = any_blocked or blocked
	for node in get_tree().get_nodes_in_group(CameraOccluder.GROUP):
		var occluder := node as CameraOccluder
		var blocked := false
		for h in sample_heights:
			if occluder.blocks_ray(base + Vector3.UP * h, to_camera):
				blocked = true
				break
		occluder.set_occluding(blocked)
		any_blocked = any_blocked or blocked
	if _player_indicator != null:
		_player_indicator.visible = any_blocked
