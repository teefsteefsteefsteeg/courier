extends "res://tests/capture_phase5h_screenshots.gd"
## Dedicated in-village view of the equipped original rod, unobstructed by shore rocks.


func _run() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_delete_save()
	await _load_level()
	var rod := inventory.get_definition(&"fishing_rod")
	inventory.add_item(rod)
	inventory.equip(rod.item_id)
	player.teleport_to(Vector3(20, 0, 20))
	player.set_physics_process(false)
	_face(player.global_position + Vector3.FORWARD)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.5
	level.add_child(camera)
	camera.position = player.global_position + Vector3(4, 3, 4)
	camera.look_at(player.global_position + Vector3.UP * 0.9)
	camera.current = true
	await _wait(60)
	var character := player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	var held := character.get_held_item_node()
	print("Generated rod grip=", held.global_position, " tip=", held.get_node("Tip").global_position)
	await _shot("19_generated_rod_in_hand")
	_delete_save()
	quit()
