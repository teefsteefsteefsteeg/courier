extends SceneTree
## Renders the village (needs a GPU window, NOT --headless) and saves screenshots
## of each location and UI screen:
##   godot --path . --script res://tests/capture_world_screenshots.gd -- <output_dir>
## Defaults to user://screenshots/world if no directory is given.

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/world")
	DirAccess.make_dir_recursive_absolute(out_dir)

	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	var dialogue := level.get_node("DialogueBox") as DialogueBox
	var journal := level.get_node("QuestJournal") as QuestJournal
	var board_ui := level.get_node("QuestBoardUI") as QuestBoardUI
	var manager := QuestManager.find(self)
	await _wait(50)
	_save(out_dir, "01_post_office_spawn.png")

	await _goto(Vector3(-15, 0, -6.8))
	_interact()
	await _wait(80)
	_save(out_dir, "02_dialogue_postmaster.png")
	dialogue.close()

	await _goto(Vector3(-11.6, 0, -9.1))
	_interact()
	await _wait(20)
	_save(out_dir, "11_quest_board.png")
	board_ui.accept_buttons[&"q001_first_delivery"].pressed.emit()
	board_ui.close()

	await _goto(Vector3(-15, 0, -6.8))
	_interact()  # Bram hands over the first delivery
	await _wait(10)
	dialogue.close()
	await _goto(Vector3(-18, 0, -1.6))
	_save(out_dir, "12_parcel_pickup.png")
	_interact()
	await _wait(10)

	await _goto(Vector3(2, 0, 0), 20.0)
	_save(out_dir, "03_village_square.png")

	await _goto(Vector3(11.4, 0, 0.1))
	_interact()  # delivers the parcel
	await _wait(80)
	_save(out_dir, "04_market_mira.png")
	dialogue.close()
	manager.accept_quest(&"q002_dragon_egg")

	await _goto(Vector3(6, 0, 18.4))
	_save(out_dir, "05_alchemy_shop.png")

	await _goto(Vector3(14, 0, -86), 16.0)
	_save(out_dir, "06_forest_gate.png")

	await _goto(Vector3(17.6, 0, -102.8))
	await _wait(30)  # let occluding trees fade
	_interact()
	await _wait(80)
	_save(out_dir, "07_clearing_elowen.png")
	dialogue.close()

	journal.open()
	await _wait(20)
	_save(out_dir, "08_journal_in_progress.png")
	journal.show_tab(QuestJournal.Tab.ARCHIVE)
	journal.select_entry(&"q001_first_delivery")
	await _wait(10)
	_save(out_dir, "09_journal_archive.png")
	journal.close()

	await _goto(Vector3(2, 0, -2.5), rig.max_zoom_size)
	await _wait(60)
	_save(out_dir, "10_overview_zoomed_out.png")
	quit()


func _goto(where: Vector3, zoom: float = 14.0) -> void:
	rig.set_zoom(zoom)
	rig.camera.size = zoom
	player.teleport_to(where)
	rig.snap_to_target()
	await _wait(40)


func _interact() -> void:
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(dir: String, file_name: String) -> void:
	var path := dir.path_join(file_name)
	var err := root.get_texture().get_image().save_png(path)
	print("saved ", path, " err=", err)
