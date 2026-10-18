extends SceneTree
## Renders the courier holding each piece of Armory equipment (GPU window, NOT
## --headless; run with --resolution 1600x900). Equips through CourierInventory so
## EquipmentStats puts the models in the hands exactly as in play. SaveGame is removed
## before the level enters the tree, so the player's real save is never read or written.
##   godot --path . --resolution 1600x900 --script res://tests/capture_equipped_weapon_screenshots.gd -- <output_dir>

const SHOTS := [
	["equipped_01_axe_and_shield", [&"battle_axe", &"wooden_shield"], true],
	["equipped_02_iron_sword", [&"iron_sword"], false],
	["equipped_03_steel_sword", [&"steel_sword"], false],
	["equipped_04_wooden_sword", [&"wooden_sword"], false],
	["equipped_05_magic_staff_hud", [&"magic_staff", &"wooden_shield"], true],
]
## Outside the Armory counter, courier turned toward the camera.
const SPOT := Vector3(5.6, 0, -11.0)

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var inventory: CourierInventory
var _hud: Array[CanvasLayer] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/equipped")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	var save := level.find_children("*", "SaveGame", true, false)
	for node in save:
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	inventory = CourierInventory.find(self)
	for node in level.find_children("*", "CanvasLayer", true, false):
		_hud.append(node as CanvasLayer)
	var toward_camera := rig.camera.global_basis.z
	toward_camera.y = 0
	for shot in SHOTS:
		for slot in [ItemDefinition.Slot.MAIN_HAND, ItemDefinition.Slot.OFF_HAND]:
			inventory.unequip(slot)
		for item_id in shot[1]:
			inventory.add_item(inventory.get_definition(item_id))
			inventory.equip(item_id)
		for layer in _hud:
			layer.visible = shot[2]
		rig.set_zoom(8.0)
		rig.camera.size = 8.0
		player.teleport_to(SPOT)
		player.facing.visual_root.rotation.y = FacingComponent.yaw_for_direction(toward_camera.rotated(Vector3.UP, deg_to_rad(-35)))
		rig.snap_to_target()
		await _wait(45)
		var path := out_dir.path_join(shot[0] + ".png")
		print("saved ", path, " err=", root.get_texture().get_image().save_png(path))
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
