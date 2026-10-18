extends SceneTree
## Renders fixed environment views for Phase 5B before/after comparison (needs a
## GPU window, NOT --headless). The HUD is hidden so the world is what's compared:
##   godot --path . --script res://tests/capture_phase5b_screenshots.gd -- <output_dir>

const VIEWS := [
	["01_post_office", Vector3(-14, 0, -6), 14.0],
	["02_town_square", Vector3(0, 0, 1), 16.0],
	["03_market", Vector3(13, 0, -1), 14.0],
	["04_alchemy_shop", Vector3(5, 0, 16), 14.0],
	["05_west_houses", Vector3(-17, 0, 8), 16.0],
	["06_forest_gate", Vector3(14, 0, -18), 16.0],
	["07_forest_clearing", Vector3(14, 0, -30), 16.0],
	["08_village_overview", Vector3(2, 0, -2.5), 22.0],
]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5b")
	DirAccess.make_dir_recursive_absolute(out_dir)

	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	for node in level.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for view in VIEWS:
		rig.set_zoom(view[2])
		rig.camera.size = view[2]
		player.teleport_to(view[1])
		rig.snap_to_target()
		await _wait(50)
		var path := out_dir.path_join(view[0] + ".png")
		print("saved ", path, " err=", root.get_texture().get_image().save_png(path))
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
