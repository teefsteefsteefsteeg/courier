extends SceneTree
## Plays run -> dash -> release in the rendered village (GPU window, NOT --headless) and
## saves a frame plus the playing clip at each step, to confirm the courier stops running
## once the dash ends:
##   godot --path . --resolution 1600x900 --script res://tests/capture_dash_animation_screenshots.gd -- <output_dir>

var player: PlayerController
var character: KayKitCharacter
var combat: CombatController
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/dash")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var level: Node3D = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	combat = player.get_node("Combat") as CombatController
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	var rig := level.get_node("IsoCameraRig") as IsoCameraRig
	player.teleport_to(Vector3(-2, 0, 4))
	rig.snap_to_target()
	await _physics(40)
	await _shot("1_idle")
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	await _physics(30)
	await _shot("2_running")
	var event := InputEventAction.new()
	event.action = &"combat_dash"
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _physics(3)
	await _shot("3_dashing")
	for action in [&"move_right", &"run", &"combat_dash"]:
		Input.action_release(action)
	while combat.is_dashing():
		await physics_frame
	await _physics(15)
	await _shot("4_after_dash_released")
	await _physics(90)
	await _shot("5_after_1_5s")
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	print("DASH %s state=%s speed=%.2f clip=%s one_shot=%s saved=%s" % [name, player.movement.get_state_name(),
		player.get_horizontal_speed(), character.current_clip, character.is_playing_one_shot(),
		root.get_texture().get_image().save_png(path)])


func _physics(frames: int) -> void:
	for i in frames:
		await physics_frame
