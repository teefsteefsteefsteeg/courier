extends SceneTree
## Renders the weapon quick-switch HUD, the Equipment window and the attack styles (GPU
## window, NOT --headless; run with --resolution 1600x900). SaveGame is removed before the
## level enters the tree, so the player's real save is never read or written.
##   godot --path . --resolution 1600x900 --script res://tests/capture_weapon_switch_screenshots.gd -- <output_dir>

const SPOT := Vector3(5.6, 0, -11.0)

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var inventory: CourierInventory
var combat: CombatController
var hud: GameplayHUD
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/weapon_switch")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	inventory = CourierInventory.find(self)
	combat = CombatController.find_on(player)
	hud = level.get_node("GameplayHUD") as GameplayHUD
	var catalog := load("res://data/shops/armory.tres") as ShopCatalog
	for item_id in [&"wooden_sword", &"battle_axe", &"magic_staff", &"wooden_shield"]:
		inventory.add_item(catalog.get_item(item_id))
	rig.set_zoom(9.0)
	rig.camera.size = 9.0
	player.teleport_to(SPOT)
	var toward_camera := rig.camera.global_basis.z
	toward_camera.y = 0
	_face(toward_camera.rotated(Vector3.UP, deg_to_rad(-35)))
	rig.snap_to_target()
	inventory.select_quick_slot(0)
	await _shot("switch_01_sword_slot1", 40)
	inventory.select_quick_slot(1)
	await _wait(20)
	combat.try_attack(toward_camera.rotated(Vector3.UP, deg_to_rad(-80)))
	await _shot("switch_02_axe_heavy_swing", 18)
	hud.equipment_ui.open()
	await _shot("switch_03_equipment_window", 20)
	hud.equipment_ui.close()
	await _wait(10)
	inventory.add_item(catalog.get_item(&"hunting_bow"))
	inventory.select_quick_slot(3)
	await _wait(25)
	var side := toward_camera.rotated(Vector3.UP, deg_to_rad(-90)).normalized()
	_face(side)
	combat.try_attack(side)
	await _shot("switch_04_bow_arrow", 6)
	quit()


func _face(direction: Vector3) -> void:
	player.facing.visual_root.rotation.y = FacingComponent.yaw_for_direction(direction)


func _shot(shot_name: String, frames: int) -> void:
	await _wait(frames)
	var path := out_dir.path_join(shot_name + ".png")
	print("saved ", path, " err=", root.get_texture().get_image().save_png(path))


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
