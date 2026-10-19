extends SceneTree
## Renders the Phase 5G features in the real village (GPU window, NOT --headless):
## the first-discovery banner, the world map with fog of war before and after exploring,
## both teleport portals inactive and active, the TELEPORT UNLOCKED notice, the destination
## menu, the trip and the courier after arriving. Portals are used through their
## Interactable, exactly as the E key does. SaveGame is removed so the real save is never
## touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase5g_screenshots.gd -- <output_dir>

## Points walked (teleported along, a few metres apart) to explore part of the map.
const EXPLORE := [Vector3(-15, 0, -2), Vector3(-6, 0, 2), Vector3(2, 0, 2), Vector3(8, 0, -1), Vector3(14, 0, 0),
		Vector3(10, 0, 8), Vector3(12, 0, 14), Vector3(6, 0, 18), Vector3(6, 0, -8), Vector3(9, 0, -13), Vector3(12, 0, -18),
		Vector3(14, 0, -22), Vector3(14, 0, -27), Vector3(13, 0, -36)]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var hud: GameplayHUD
var map: Node
var out_dir: String
var prefix: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase5g")
	DirAccess.make_dir_recursive_absolute(out_dir)
	prefix = "%dx%d_" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	hud = level.get_node("GameplayHUD") as GameplayHUD
	map = hud.get_node("Minimap")
	await _wait(25)
	await _shot("01_discovery_banner", 20)
	map.set_expanded(true)
	await _shot("02_world_map_start_fog", 10)
	map.set_expanded(false)
	for point in EXPLORE:
		player.teleport_to(point)
		rig.snap_to_target()
		await _wait(8)
	await _wait(10)
	await _shot("03_forest_discovered", 40)
	map.set_expanded(true)
	await _shot("04_world_map_explored", 10)
	map.set_expanded(false)
	var village := TeleportPortal.find(self, &"willowmere_portal")
	var forest := TeleportPortal.find(self, &"whisperwood_portal")
	await _stand_at(village)
	await _shot("05_village_portal_inactive", 30)
	village.interactable.interact(player)
	await _shot("06_village_teleport_unlocked", 20)
	await _shot("07_village_portal_active", 70)
	await _stand_at(forest)
	await _shot("08_forest_portal_inactive", 30)
	forest.interactable.interact(player)
	await _shot("09_forest_teleport_unlocked", 25)
	await _wait(80)
	forest.interactable.interact(player)
	await _shot("10_teleport_menu", 10)
	hud.teleport_menu.choose(&"willowmere_portal")
	await _shot("11_teleport_fade", 14)
	await _shot("12_after_teleport", 50)
	map.set_expanded(true)
	await _shot("13_world_map_portals", 10)
	map.set_expanded(false)
	quit()


## Puts the courier on the portal's arrival spot, facing it.
func _stand_at(portal: TeleportPortal) -> void:
	player.teleport_to(portal.get_arrival_position())
	rig.snap_to_target()
	await _wait(20)


func _shot(shot_name: String, frames: int) -> void:
	await _wait(frames)
	var path := out_dir.path_join(prefix + shot_name + ".png")
	print("saved ", path, " err=", root.get_texture().get_image().save_png(path))


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
