extends SceneTree
## Renders the Phase 2 sandbox (needs a GPU window, NOT --headless) and saves screenshots.
##   godot --path . --script res://tests/capture_phase2_screenshots.gd -- <output_dir>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots_phase2")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var level: Node3D = (load("res://scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	var rig := level.get_node("IsoCameraRig") as IsoCameraRig
	var board := level.get_node("PostOffice/QuestBoard") as QuestBoard
	var board_ui := level.get_node("QuestBoardUI") as QuestBoardUI
	await _wait(60)
	_save(out_dir, "01_post_office.png")

	_place(player, rig, Vector3(0, 0, -2))
	await _wait(20)
	board.interactable.interact(player)
	await _wait(20)
	_save(out_dir, "02_quest_board.png")
	board_ui.accept_buttons[&"q001_first_delivery"].pressed.emit()
	await _wait(10)
	_save(out_dir, "03_board_after_accept.png")
	board_ui.close()

	var postmaster := level.get_node("NPCs/Postmaster") as NPC
	postmaster.interactable.interact(player)
	await _wait(10)
	(level.get_node("PostOffice/Pickups/ParcelPickup") as PackagePickup).interactable.interact(player)
	var merchant := level.get_node("NPCs/Merchant") as NPC
	_place(player, rig, merchant.global_position + Vector3(-1.6, 0, 0.6))
	await _wait(40)
	_save(out_dir, "04_carrying_near_merchant.png")
	(level.get_node("NPCs/Alchemist") as NPC).interactable.interact(player)
	merchant.interactable.interact(player)
	await _wait(30)
	_save(out_dir, "05_delivered.png")

	rig.set_zoom(rig.max_zoom_size)
	_place(player, rig, Vector3(-8, 0, 4))
	await _wait(90)
	_save(out_dir, "06_overview.png")
	quit()


func _place(player: PlayerController, rig: IsoCameraRig, at: Vector3) -> void:
	player.teleport_to(at)
	rig.snap_to_target()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(dir: String, file_name: String) -> void:
	var path := dir.path_join(file_name)
	var err := root.get_texture().get_image().save_png(path)
	print("saved ", path, " err=", err)
