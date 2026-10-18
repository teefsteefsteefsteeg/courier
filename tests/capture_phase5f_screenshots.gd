extends SceneTree
## Renders the village buildings from fixed cameras for the Phase 5F before/after
## comparison (GPU window, NOT --headless; run with --resolution 1600x900). Each
## building view stands on the camera side of one building; the "_hud" views keep the gameplay
## HUD so the change is judged as it is actually played.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase5f_screenshots.gd -- <output_dir>

const VIEWS := [
	["01_overview", Vector3(0, 0, 4), 22.0, false],
	["02_plaza_north", Vector3(-6, 0, -8), 18.0, false],
	["03_alchemy_shop", Vector3(6.5, 0, 15.5), 12.0, false],
	["04_cottage_rose", Vector3(-5.5, 0, 16.5), 12.0, false],
	["05_cottage_oak", Vector3(-14.5, 0, 13.5), 12.0, false],
	["06_cottage_fern", Vector3(20.5, 0, 16.5), 12.0, false],
	["07_cottage_blue", Vector3(-1.5, 0, -13.5), 12.0, false],
	["08_mill", Vector3(27.5, 0, -2.5), 14.0, false],
	["09_blacksmith", Vector3(-23.5, 0, -0.5), 13.0, false],
	["10_inn", Vector3(-19.5, 0, 25.5), 13.0, false],
	["11_cottage_brook", Vector3(16.5, 0, 29.5), 12.0, false],
	["12_cottage_moss", Vector3(-3.5, 0, 30.5), 12.0, false],
	["13_residential_south", Vector3(-4, 0, 20), 20.0, false],
	["14_residential_west", Vector3(-20, 0, 8), 20.0, false],
	["15_gameplay_plaza_hud", Vector3(1, 0, 2), 14.0, true],
	["16_gameplay_south_lane_hud", Vector3(4, 0, 20), 14.0, true],
]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var _hud: Array[CanvasLayer] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5f")
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
