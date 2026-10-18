extends SceneTree
## Renders the actual village showcase and the live gameplay HUD.
## Run: godot --path . --script res://tests/capture_phase3_showcase_screenshots.gd -- docs/screenshots/phase3

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "docs/screenshots/phase3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))
	var village := (load("res://scenes/levels/village.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(village)
	current_scene = village
	var player := village.get_node("Player") as PlayerController
	var rig := village.get_node("IsoCameraRig") as IsoCameraRig
	var showcase := village.get_node("PostOffice/Phase3Showcase") as Phase3Showcase
	player.teleport_to(Vector3(-13.2, 0, -1.6))
	rig.camera.size = 8.0
	rig.set_zoom(8.0)
	rig.snap_to_target()
	await _wait(120)
	_save(out_dir, "01_arcane_cargo_egg_hud.png")
	showcase.interactable.interact(player)
	# Capture the potion during its volatile warning phase, not its calm trough.
	await _wait(260)
	_save(out_dir, "02_arcane_cargo_potion_hud.png")
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(dir: String, file_name: String) -> void:
	var path := "res://" + dir.path_join(file_name)
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("saved ", path, " error=", error)
