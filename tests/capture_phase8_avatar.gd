extends SceneTree
## Renders Phase 8 milestone 4 (animated HUD avatar) in the real village (GPU window, NOT
## --headless): full-screen shots of the status panel while idle, just after a hit, at low
## health and while cheering, plus a strip of portrait crops over two seconds of idling to
## show it moves. SaveGame is removed.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_avatar.gd -- <output_dir>

var level: Node3D
var player: PlayerController
var out_dir: String
var problems: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase8")
	DirAccess.make_dir_recursive_absolute(out_dir)
	UISettings.persist = false
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	(level.get_node("IsoCameraRig") as IsoCameraRig).set_process_unhandled_input(false)
	await _seconds(1.5)
	var live := level.find_children("*", "AnimatedPortrait", true, false)[0] as AnimatedPortrait
	var health := CombatController.find_on(player).health
	var portrait_rect := Rect2(Vector2(22, 22), Vector2(84, 84))
	var frames: Array[Image] = []
	for i in 8:
		await RenderingServer.frame_post_draw
		frames.append(root.get_texture().get_image().get_region(Rect2i(portrait_rect)))
		await _seconds(0.3)
	live._glance_left = 0.0
	await _seconds(0.9)
	await RenderingServer.frame_post_draw
	frames.append(root.get_texture().get_image().get_region(Rect2i(portrait_rect)))
	var strip := Image.create(84 * frames.size(), 84, false, Image.FORMAT_RGBA8)
	var differing := 0
	for i in frames.size():
		frames[i].convert(Image.FORMAT_RGBA8)
		strip.blit_rect(frames[i], Rect2i(0, 0, 84, 84), Vector2i(84 * i, 0))
		if i > 0 and frames[i].get_data() != frames[0].get_data():
			differing += 1
	strip.resize(strip.get_width() * 2, 168, Image.INTERPOLATE_NEAREST)
	strip.save_png(out_dir.path_join("28_avatar_idle_frames.png"))
	_expect(differing >= 4, "the portrait changes over time (%d of %d frames differ from the first)" % [differing, frames.size() - 1])
	await _shot("29_avatar_idle_hud")
	health.apply_damage(12.0, player.global_position + Vector3.FORWARD)
	await _seconds(0.12)
	_expect(live.mood == &"hit", "flinch on the hit")
	await _shot("30_avatar_hit")
	await _seconds(1.0)
	health.apply_damage(health.get_health() - 14.0, Vector3.ZERO)
	await _seconds(0.9)
	_expect(live.is_low(), "low health")
	await _shot("31_avatar_low_health")
	health.heal(100.0)
	await _seconds(0.6)
	QuestManager.find(self).quest_rewarded.emit(&"capture", null)
	await _seconds(0.45)
	_expect(live.mood == &"cheer", "cheering")
	await _shot("32_avatar_cheer")
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
