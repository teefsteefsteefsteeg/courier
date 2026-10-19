extends SceneTree
## Renders the courier status HUD in the real village (GPU window, NOT --headless):
## full health, a hit (pale damage chip draining), low health, healing, reputation
## progress and a rank-up, the package shield up, and an active quest tracker under the
## panel. Run once per window size, e.g. --resolution 1600x900, 1280x720 and a phone's
## 19.5:9 landscape 1560x720 (canvas_items/expand stretching widens the logical view there).
## SaveGame is removed before the level enters the tree (the real save is never touched).
##   godot --path . --resolution 1600x900 --script res://tests/capture_status_hud_screenshots.gd -- <output_dir>

const SPOT := Vector3(2.0, 0, 2.0)

var level: Node3D
var player: PlayerController
var health: CombatHealth
var wallet: CourierWallet
var out_dir: String
var prefix: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/status_hud")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var view := root.get_visible_rect().size
	prefix = "%dx%d_" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	var rig := level.get_node("IsoCameraRig") as IsoCameraRig
	await _wait(40)
	health = CombatController.find_on(player).health
	wallet = CourierWallet.find(self)
	player.teleport_to(SPOT)
	rig.snap_to_target()
	print("logical viewport ", view)
	await _shot("01_full_health", 30)
	health.apply_damage(45.0, player.global_position + Vector3.RIGHT)
	await _shot("02_hit_damage_chip", 8)
	await _shot("03_after_hit", 70)
	health.apply_damage(35.0, player.global_position + Vector3.RIGHT)
	await _shot("04_low_health", 70)
	health.heal(50.0)
	await _shot("05_healing_flash", 6)
	wallet.add_reputation(9)
	await _shot("06_reputation_progress", 80)
	wallet.add_reputation(8)
	await _shot("07_rank_up", 12)
	var quests := level.find_children("*", "QuestManager", true, false)
	if not quests.is_empty():
		(quests[0] as QuestManager).accept_quest(&"q001_first_delivery")
	health.heal(100.0)
	await _shot("08_quest_tracker_below", 90)
	quit()


func _shot(shot_name: String, frames: int) -> void:
	await _wait(frames)
	var path := out_dir.path_join(prefix + shot_name + ".png")
	print("saved ", path, " err=", root.get_texture().get_image().save_png(path))


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
