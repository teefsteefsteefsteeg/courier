extends SceneTree
## Renders the pixel-art input prompts in the village HUD (GPU window, NOT --headless):
##   godot --path . --resolution 1600x900 --script res://tests/capture_input_prompt_screenshots.gd -- <output_dir>

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/input_prompts")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	var manager := QuestManager.find(self)
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	var mira := level.get_node("NPCs/MerchantMira") as NPC
	var board := level.get_node("PostOffice/Markers/QuestBoardSpot/QuestBoard") as Node3D
	await _wait(30)
	await _shot("01_spawn_onboarding")

	await _stand_near(bram, bram.global_position + Vector3(0, 0, 1.4))
	await _shot("02_near_bram")
	await _stand_near(board, board.global_position + Vector3(0, 0, 2))
	await _shot("03_near_board")

	manager.accept_quest(&"q001_first_delivery")
	await _stand_near(bram, bram.global_position + Vector3(0, 0, 1.4))
	bram.interactable.interact(player)
	await _wait(120)
	await _shot("04_dialogue")
	(level.get_node("DialogueBox") as DialogueBox).close()

	for node in level.get_node("PostOffice/Markers/ParcelPickupSpot").get_children():
		var pickup := node as PackagePickup
		if pickup != null and pickup.package_definition.package_id == &"pkg_ordinary_parcel":
			pickup.interactable.interact(player)
	await _stand_near(mira, (level.get_node("Markers/MarketDeliverySpot") as Node3D).global_position)
	await _shot("05_carrying_near_mira")

	(level.get_node("QuestJournal") as QuestJournal).open()
	await _wait(10)
	await _shot("06_journal")
	(level.get_node("QuestJournal") as QuestJournal).close()
	level.get_node("GameplayHUD/Minimap").set_expanded(true)
	await _wait(10)
	await _shot("07_map")
	quit()


func _stand_near(target: Node3D, toward: Vector3, distance: float = 1.3) -> void:
	var offset := toward - target.global_position
	offset.y = 0.0
	player.teleport_to(target.global_position + offset.normalized() * distance)
	rig.snap_to_target()
	await _wait(40)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	print("saved ", path, " err=", root.get_texture().get_image().save_png(path))


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
