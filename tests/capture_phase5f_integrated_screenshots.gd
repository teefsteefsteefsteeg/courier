extends SceneTree
## Integrated Phase 5F walkthrough in the rendered village (GPU window, NOT --headless):
## spawn HUD, the Armory, Brenna's prompt and keycap, her shop, and a dash that must end
## in Idle. Uses its own save file; a windowed debug run is development mode (500 gold).
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase5f_integrated_screenshots.gd -- <output_dir>

const SAVE_PATH := "user://capture_integrated_save.json"

var out_dir: String
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5f_integrated")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var level: Node3D = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = SAVE_PATH
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	await _wait(60)
	await _shot("1_spawn")

	var armory := level.find_children("*", "Armory", true, false)[0] as Armory
	player.teleport_to(armory.get_shop_front().global_position + Vector3(0, 0, 4))
	rig.snap_to_target()
	await _wait(40)
	await _shot("2_armory")
	player.teleport_to(armory.get_shop_front().global_position)
	rig.snap_to_target()
	await _wait(40)
	print("INTEG prompt='%s' badge=%s rect=%s" % [prompt.label.text, prompt.world_badge.visible, prompt.world_badge.get_global_rect()])
	await _shot("3_brenna_prompt")
	player.interaction.try_interact(player)
	await _wait(10)
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	print("INTEG shop_open=%s title=%s gold=%d" % [shop.is_open(), shop.title_label.text, CourierWallet.find(self).gold])
	await _shot("4_brenna_shop")
	shop.activate(&"magic_staff")
	shop.activate(&"magic_staff")
	await _wait(5)
	await _shot("5_staff_bought")
	shop.close()
	await _wait(10)

	var combat := player.get_node("Combat") as CombatController
	var character := player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	player.teleport_to(Vector3(-2, 0, 4))
	rig.snap_to_target()
	await _wait(30)
	Input.action_press(&"move_right")
	Input.action_press(&"run")
	for i in 30:
		await physics_frame
	combat.try_dash()
	await physics_frame
	print("INTEG dashing clip=%s" % character.current_clip)
	Input.action_release(&"move_right")
	Input.action_release(&"run")
	while combat.is_dashing():
		await physics_frame
	for i in 60:
		await physics_frame
	print("INTEG after_dash state=%s speed=%.2f clip=%s one_shot=%s" % [player.movement.get_state_name(), player.get_horizontal_speed(), character.current_clip, character.is_playing_one_shot()])
	await _shot("6_after_dash_idle")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	print("INTEG saved %s err=%s" % [path, root.get_texture().get_image().save_png(path)])


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
