extends SceneTree
## Renders character close-ups for Phase 5C before/after comparison (needs a GPU
## window, NOT --headless). Uses only gameplay APIs, so it runs on older phases too:
##   godot --path . --script res://tests/capture_phase5c_screenshots.gd -- <output_dir>

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5c")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	for node in level.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	for node in level.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false

	await _shot(out_dir, "01_player_idle", Vector3(-13, 0, -4.5), 7.0)
	await _face_npc("PostmasterBram", Vector3(-14.2, 0, -6.6))
	await _shot(out_dir, "02_postmaster_bram", Vector3(-14.2, 0, -6.6), 7.0)
	await _face_npc("MerchantMira", Vector3(11.6, 0, 0.6))
	await _shot(out_dir, "03_merchant_mira", Vector3(11.6, 0, 0.6), 7.0)
	await _face_npc("AlchemistCorvin", Vector3(5.6, 0, 18.2))
	await _shot(out_dir, "04_alchemist_corvin", Vector3(5.6, 0, 18.2), 7.0)
	await _face_npc("VillagerPip", Vector3(3.9, 0, 3.9))
	await _shot(out_dir, "05_villager_pip", Vector3(3.9, 0, 3.9), 7.0)
	await _face_npc("MageElowen", Vector3(15.0, 0, -101.0))
	await _shot(out_dir, "06_mage_elowen", Vector3(15.0, 0, -101.0), 7.0)
	# Walking through the square (input held, so movement and animation are live).
	player.teleport_to(Vector3(-3, 0, 2))
	rig.set_zoom(8.0); rig.camera.size = 8.0; rig.snap_to_target()
	await _wait(10)
	Input.action_press(&"move_right")
	await _wait(35)
	_save(out_dir, "07_player_walking")
	Input.action_press(&"run")
	await _wait(30)
	_save(out_dir, "08_player_running")
	Input.action_release(&"run")
	Input.action_release(&"move_right")
	# Casting a magic bolt in the forest.
	player.teleport_to(Vector3(13, 0, -94))
	rig.snap_to_target()
	await _wait(40)
	var combat := CombatController.find_on(player)
	if combat != null:
		combat.try_magic_bolt(Vector3(0, 0, -1))
	await _wait(14)
	_save(out_dir, "09_player_casting")
	quit()


func _face_npc(npc_name: String, from: Vector3) -> void:
	player.teleport_to(from)
	await _wait(5)
	var npc := level.get_node("NPCs/" + npc_name) as NPC
	npc.interactable.interacted.emit(player)


func _shot(dir: String, file_name: String, at: Vector3, zoom: float) -> void:
	rig.set_zoom(zoom)
	rig.camera.size = zoom
	player.teleport_to(at)
	rig.snap_to_target()
	await _wait(45)
	_save(dir, file_name)


func _save(dir: String, file_name: String) -> void:
	var path := dir.path_join(file_name + ".png")
	print("saved ", path, " err=", root.get_texture().get_image().save_png(path))


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
