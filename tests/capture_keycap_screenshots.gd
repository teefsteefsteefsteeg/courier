extends SceneTree
## Renders the HUD keyboard guide (GPU window, NOT --headless): all keys released, W held,
## W + D held, W + A held, and M / J / Shift / Space held. Keys are held through the real
## InputMap actions. SaveGame is removed so the real save is never touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_keycap_screenshots.gd -- <output_dir>

const SHOTS := [
	["keys_01_released", []],
	["keys_02_w_held", [&"move_forward"]],
	["keys_03_w_d_held", [&"move_forward", &"move_right"]],
	["keys_04_w_a_held", [&"move_forward", &"move_left"]],
	["keys_05_m_j_shift_space_held", [&"toggle_map", &"toggle_journal", &"run", &"combat_magic_bolt"]],
]

var level: Node3D
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/keycaps")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	await _wait(40)
	# Hold the keys without moving the courier, so every shot frames the same scene.
	player.input_enabled = false
	var prefix := "%dx%d_" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	for shot in SHOTS:
		for action in shot[1]:
			Input.action_press(action)
		await _wait(12)
		var path := out_dir.path_join(prefix + shot[0] + ".png")
		print("saved ", path, " err=", root.get_texture().get_image().save_png(path))
		for action in shot[1]:
			Input.action_release(action)
		await _wait(12)
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
