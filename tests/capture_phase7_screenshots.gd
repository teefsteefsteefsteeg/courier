extends SceneTree
## Renders the Phase 7 Milestone A changes in the real village (GPU window, NOT --headless):
## the village and the Whisperwood from above, the Courier Guild board on the plaza, the post
## office without the cargo exhibit, Bram and Brenna turning to the courier, the widened
## roads, the forest edge gate, trail, glades and clearing, and the world map. NPCs are talked
## to through their Interactable, exactly as the E key does. SaveGame is removed so the real
## save is never touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase7_screenshots.gd -- <output_dir>

## name, courier position, camera zoom (orthographic size)
const SHOTS := [
	["07_widened_forest_road", Vector3(9.6, 0, -12.4), 20.0],
	["08_forest_edge_gate", Vector3(14.6, 0, -48.5), 14.0],
	["09_whisperwood_trail", Vector3(16, 0, -66), 14.0],
	["10_fern_glade", Vector3(-1, 0, -79), 14.0],
	["11_forest_gate", Vector3(14, 0, -86), 14.0],
	["12_moonstone_clearing", Vector3(14, 0, -100), 16.0],
	["13_hollow_glade", Vector3(33, 0, -89), 14.0],
]

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var hud: GameplayHUD
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase7")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	hud = level.get_node("GameplayHUD") as GameplayHUD
	await _wait(30)

	await _top_down("01_village_from_above", Vector2(0, -2), 92.0)
	var board := level.get_node("PostOffice/Markers/QuestBoardSpot/QuestBoard") as Node3D
	await _goto(board.global_position + board.global_basis.z * 1.6, 14.0)
	await _shot("02_guild_board_on_plaza")
	await _goto(board.global_position + board.global_basis.z * 1.6, 8.0)
	await _shot("03_guild_board_closeup")
	await _goto(Vector3(-12.5, 0, -4.5), 12.0)
	await _shot("04_post_office_without_exhibit")

	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	await _goto(bram.global_position + bram.global_basis.x * 2.0, 9.0)
	bram.interactable.interact(player)
	await _seconds(1.2)
	await _shot("05_bram_turns_to_courier")
	_close_dialogue()
	var brenna := level.get_node("Armory/Merchant") as NPC
	var front := (level.get_node("Armory") as Armory).get_shop_front()
	await _goto(front.global_position + Vector3(1.2, 0, 0), 9.0)
	brenna.interactable.interact(player)
	await _seconds(1.2)
	for shop: ShopUI in level.find_children("*", "ShopUI", true, false):
		if shop.is_open():
			shop.close()
	await _seconds(0.2)
	await _shot("06_brenna_turns_to_courier")

	for spec in SHOTS:
		await _goto(spec[1], spec[2])
		await _seconds(0.6)  # let the trees in front fade
		await _shot(spec[0])
	await _top_down("14_whisperwood_from_above", Vector2(12, -86), 90.0)
	hud.get_node("Minimap").set_expanded(true)
	await _wait(10)
	await _shot("15_world_map")
	hud.get_node("Minimap").set_expanded(false)
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _goto(at: Vector3, zoom: float) -> void:
	player.teleport_to(at)
	rig.zoom_size = zoom
	rig.snap_to_target()
	await _wait(30)


func _close_dialogue() -> void:
	var dialogue := level.get_node("DialogueBox")
	if dialogue.has_method(&"close"):
		dialogue.call(&"close")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


## An orthographic view straight down, without the HUD.
func _top_down(name: String, centre: Vector2, span: float) -> void:
	var layers: Array[CanvasLayer] = []
	for node in level.get_children():
		if node is CanvasLayer and (node as CanvasLayer).visible:
			layers.append(node)
			(node as CanvasLayer).visible = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = span
	camera.far = 200.0
	level.add_child(camera)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), Vector3(centre.x, 60, centre.y))
	var previous := root.get_camera_3d()
	camera.make_current()
	await _wait(20)
	await _shot(name)
	camera.queue_free()
	if previous != null:
		previous.make_current()
	for layer in layers:
		layer.visible = true
