extends SceneTree
## Renders the Armory shop window (GPU window, NOT --headless). A windowed debug run is
## development mode, so the courier starts with the 500 test gold. Uses its own save file.
##   godot --path . --resolution 1600x900 --script res://tests/capture_armory_shop_screenshots.gd -- <output_dir>

const SAVE_PATH := "user://capture_armory_save.json"

var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/armory")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var level: Node3D = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = SAVE_PATH
	root.add_child(level)
	current_scene = level
	var player: PlayerController = level.get_node("Player")
	var rig := level.get_node("IsoCameraRig") as IsoCameraRig
	var counter := (load("res://scenes/gameplay/shop/merchant_counter.tscn") as PackedScene).instantiate() as Node3D
	level.add_child(counter)
	counter.global_position = Vector3(0, 0, 4)
	player.teleport_to(Vector3(0, 0, 5.2))
	rig.snap_to_target()
	await _wait(40)
	print("ARMORY dev=%s gold=%d" % [DevMode.is_enabled(), CourierWallet.find(self).gold])
	await _shot("1_counter_prompt")
	player.interaction.try_interact(player)
	await _wait(10)
	await _shot("2_shop_open")
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	shop.activate(&"wooden_sword")
	shop.activate(&"iron_sword")
	shop.activate(&"iron_sword")
	await _wait(5)
	await _shot("3_bought_and_equipped")
	shop.close()
	await _wait(20)
	await _shot("4_iron_sword_in_hand")
	print("ARMORY gold=%d owned=%s bolt_damage=%.1f" % [CourierWallet.find(self).gold, CourierInventory.find(self).get_owned_ids(), (player.get_node("Combat") as CombatController).bolt_damage])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	print("ARMORY saved ", path, " err=", root.get_texture().get_image().save_png(path))


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
