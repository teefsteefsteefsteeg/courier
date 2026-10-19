extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 10:
		await physics_frame
	for point: Vector3 in [Vector3(-33,1,3),Vector3(-33,1,8),Vector3(20,1,-23),Vector3(26,1,-27.5),Vector3(33,1,-31.5)]:
		var shape := SphereShape3D.new()
		shape.radius = 2.5
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.transform.origin = point
		print("NAV_AT ", point)
		for hit in root.world_3d.direct_space_state.intersect_shape(query,30):
			print("  ",hit.collider.get_path()," pos=",hit.collider.global_position)
	root.remove_child(level)
	level.free()
	quit()
