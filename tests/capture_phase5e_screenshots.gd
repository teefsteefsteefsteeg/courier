extends SceneTree
## Renders the village from fixed cameras for Phase 5E before/after comparison
## (GPU window, NOT --headless; run with --resolution 1600x900). The "_hud" views
## keep the gameplay HUD so the change is judged as it is actually played.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase5e_screenshots.gd -- <output_dir>

const VIEWS := [
	["01_overview", Vector3(2, 0, -2.5), 22.0, false],
	["02_plaza", Vector3(0, 0, 1), 14.0, false],
	["03_market", Vector3(14, 0, -0.5), 14.0, false],
	["04_post_office", Vector3(-12, 0, -4), 14.0, false],
	["05_residential_west", Vector3(-18, 0, 5), 16.0, false],
	["06_residential_south", Vector3(-6, 0, 20), 16.0, false],
	["07_alchemy_lane", Vector3(7, 0, 15), 14.0, false],
	["08_farm_east", Vector3(28, 0, -6), 18.0, false],
	["09_farm_west", Vector3(-30, 0, -6), 16.0, false],
	["10_forest_entrance", Vector3(11, 0, -14), 16.0, false],
	["11_village_edge", Vector3(-34, 0, 26), 18.0, false],
	["12_gameplay_plaza_hud", Vector3(1, 0, 2), 14.0, true],
	["13_gameplay_forest_road_hud", Vector3(9, 0, -11), 14.0, true],
	["14_west_edge", Vector3(-38, 0, 4), 22.0, false],
	["15_south_edge", Vector3(6, 0, 38), 22.0, false],
]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var _hud: Array[CanvasLayer] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5e")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	for node in level.find_children("*", "CanvasLayer", true, false):
		_hud.append(node as CanvasLayer)
	for view in VIEWS:
		for layer in _hud:
			layer.visible = view[3]
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
