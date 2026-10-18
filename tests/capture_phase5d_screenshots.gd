extends SceneTree
## Renders the Phase 5D pilot locations from fixed cameras for before/after comparison
## (needs a GPU window, NOT --headless). HUD and labels are hidden:
##   godot --path . --script res://tests/capture_phase5d_screenshots.gd -- <output_dir>

const VIEWS := [
	["01_post_office_south", Vector3(-14, 0, -2.5), 11.0],
	["02_post_office_interior", Vector3(-15, 0, -7.5), 9.0],
	["03_house_rose", Vector3(-8, 0, 15), 9.0],
	["04_house_fern", Vector3(18, 0, 15), 9.0],
	["05_farm_edge", Vector3(24, 0, -12.5), 12.0],
	["06_forest_path", Vector3(14, 0, -24), 11.0],
]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5d")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	for node in level.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in level.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
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
