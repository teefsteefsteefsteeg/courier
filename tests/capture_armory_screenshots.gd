extends SceneTree
## Renders Willowmere's armory (Phase 5F) from fixed cameras (GPU window, NOT
## --headless; run with --resolution 1600x900). The "_hud" view keeps the
## gameplay HUD with the courier at the counter, as it is actually played.
##   godot --path . --resolution 1600x900 --script res://tests/capture_armory_screenshots.gd -- <output_dir>

const VIEWS := [
	["armory_01_shopfront", Vector3(8.0, 0, -11.0), 11.0, false],
	["armory_02_from_plaza", Vector3(2.5, 0, -6.0), 16.0, false],
	["armory_03_counter_hud", Vector3(5.9, 0, -12.85), 12.0, true],
	["armory_04_overview", Vector3(3.0, 0, -9.0), 22.0, false],
]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var _hud: Array[CanvasLayer] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/armory")
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
