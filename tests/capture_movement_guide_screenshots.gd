extends SceneTree
## Renders the HUD movement guide (GPU window, NOT --headless) and prints where it is:
##   godot --path . --resolution 1600x900 --script res://tests/capture_movement_guide_screenshots.gd -- <output_dir> [canvas WxH]
## The optional canvas size (e.g. 1280x720) also shrinks the 2D canvas itself (no stretch),
## the worst case for HUD layout.

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var hud: GameplayHUD
var out_dir: String
var tag: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/movement_guide")
	DirAccess.make_dir_recursive_absolute(out_dir)
	tag = "%dx%d" % [root.size.x, root.size.y]
	if args.size() > 1:
		var parts := args[1].split("x")
		var canvas := Vector2i(int(parts[0]), int(parts[1]))
		root.content_scale_size = canvas
		tag = "canvas%s" % args[1]
	UISettings.persist = false
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	hud = level.get_node("GameplayHUD")
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	await _wait(40)
	await _shot("1_spawn")

	var manager := QuestManager.find(self)
	manager.accept_quest(&"q001_first_delivery")
	await _wait(10)
	await _shot("2_contract")
	var carrier := PackageCarrier.find_on(player)
	carrier.pick_up(PackageInstance.new(load("res://data/packages/pkg_ordinary_parcel.tres")))
	await _wait(10)
	await _shot("3_carrying")
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	player.teleport_to(bram.global_position + Vector3(0, 0, 1.3))
	rig.snap_to_target()
	await _wait(20)
	bram.interactable.interact(player)
	await _wait(60)
	await _shot("4_dialogue")
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var guide := hud.movement_guide
	var keys: PackedStringArray = []
	for action in MovementGuide.ACTIONS:
		var keycap := guide.keycaps.get(action) as Control
		var rect := keycap as TextureRect
		keys.append(rect.texture.resource_path.get_file().get_basename() if rect != null else "fallback")
	var overlaps: PackedStringArray = []
	for node in get_nodes_in_group(InputPrompt.AVOID_GROUP):
		var control := node as Control
		if control != guide and control.is_visible_in_tree() and guide.is_visible_in_tree() and control.get_global_rect().intersects(guide.get_global_rect()):
			overlaps.append(control.name)
	var path := out_dir.path_join("%s_%s.png" % [tag, name])
	print("GUIDE %s %s visible=%s rect=%s canvas=%s keys=%s overlaps=%s saved=%s" % [
		tag, name, guide.is_visible_in_tree(), guide.get_global_rect(), root.get_visible_rect().size, keys, overlaps,
		root.get_texture().get_image().save_png(path)])


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
