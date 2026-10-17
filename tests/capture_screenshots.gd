extends SceneTree
## Renders the main scene (needs a GPU window, NOT --headless) and saves screenshots.
##   godot --path . --script res://tests/capture_screenshots.gd -- <output_dir>
## Defaults to user://screenshots if no directory is given.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var level: Node3D = (load("res://scenes/levels/test_yard.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var player := level.get_node("Player") as PlayerController
	var rig := level.get_node("IsoCameraRig") as IsoCameraRig
	await _wait(60)
	_save(out_dir, "01_spawn.png")

	# Walk diagonally for a moment to show facing + follow.
	Input.action_press(&"move_forward")
	Input.action_press(&"move_right")
	await _wait(40)
	Input.action_release(&"move_forward")
	Input.action_release(&"move_right")
	_save(out_dir, "02_moving.png")

	# Stand next to the Postmaster and talk.
	var npc := level.get_node("NPCs/Postmaster") as NPC
	player.teleport_to(npc.global_position + Vector3(1.4, 0, 1.0))
	rig.snap_to_target()
	await _wait(30)
	_save(out_dir, "03_prompt.png")
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(40)
	_save(out_dir, "04_talking.png")

	rig.set_zoom(rig.max_zoom_size)
	player.teleport_to(Vector3.ZERO)
	rig.snap_to_target()
	await _wait(90)
	_save(out_dir, "05_zoomed_out.png")
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(dir: String, file_name: String) -> void:
	var path := dir.path_join(file_name)
	var err := root.get_texture().get_image().save_png(path)
	print("saved ", path, " err=", err)
