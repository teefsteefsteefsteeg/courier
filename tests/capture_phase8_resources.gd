extends SceneTree
## Renders Phase 8 milestone 2 in the real game (GPU window, NOT --headless): the village
## rubble with its countdown-free prompt, then Runewood's new tool sites worked with the
## real interact key (tree before / chopping / stump "regrowing", ore rock, the Moonbrook
## fishing spot with the bobber in the river). SaveGame is removed and UISettings does not
## persist, so the player's real save and settings are never touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_resources.gd -- <output_dir>

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var inventory: CourierInventory
var user: ToolUser
var router: Node
var out_dir: String
var problems: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase8")
	DirAccess.make_dir_recursive_absolute(out_dir)
	UISettings.persist = false
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	rig.set_process_unhandled_input(false)
	await _wait(40)
	inventory = CourierInventory.find(self)
	user = ToolUser.find_on(player)
	router = get_first_node_in_group(&"phase6_router")
	for id in [&"woodcutter_axe", &"miner_pickaxe", &"fishing_rod", &"iron_sword"]:
		inventory.add_item(inventory.get_definition(id))

	# Village: mine a quarry rock, then show the rubble's prompt (no countdown).
	var rock := level.get_node("ToolSites/QuarryRock2") as HarvestNode
	inventory.equip(&"miner_pickaxe")
	await _stand(rock, Vector3(1.1, 0, 0.9), 9.0)
	await _key(KEY_E)
	await _finish()
	await _wait(10)
	_expect(not rock.is_available() and not rock.get_interaction_prompt(player).contains(":"), "village rock depleted, prompt '%s'" % rock.get_interaction_prompt(player))
	await _shot("07_village_rubble_no_countdown")

	# Runewood.
	router.call(&"travel", &"runewood", &"Arrival", player)
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == &"runewood" and not router.get(&"crossing"):
			break
	await _wait(20)
	var sites := (router.get(&"active_level") as Node).get_node("RunewoodToolSites") as GroundSnap
	if not sites.is_snapped:
		await sites.snapped
	var tree := sites.get_node("RunewoodTree1") as HarvestNode
	inventory.equip(&"woodcutter_axe")
	await _stand(tree, Vector3(1.2, 0, 1.2), 8.0)
	await _shot("08_runewood_marked_tree")
	await _key(KEY_E)
	_expect(user.state == ToolUser.State.WORKING, "chopping in Runewood")
	await _seconds(1.6)
	await _shot("09_runewood_chopping")
	await _finish()
	await _wait(20)
	_expect(not tree.is_available() and tree.depleted_visual.visible, "Runewood tree became a stump")
	await _shot("10_runewood_stump_regrowing")
	var ore := sites.get_node("RunewoodRock1") as HarvestNode
	inventory.equip(&"miner_pickaxe")
	await _stand(ore, Vector3(1.1, 0, 0.9), 8.0)
	await _key(KEY_E)
	await _seconds(1.0)
	await _shot("11_runewood_mining")
	await _finish()
	_expect(not ore.is_available(), "Runewood rock mined")
	var spot := sites.get_node("MoonbrookBank") as FishingSpot
	inventory.equip(&"fishing_rod")
	await _stand(spot, Vector3(0, 0, 0.4), 9.0)
	await _key(KEY_E)
	await _seconds(2.2)
	_expect(user.state == ToolUser.State.FISHING, "fishing in the Moonbrook")
	await _shot("12_runewood_moonbrook_fishing")
	user.cancel()
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _stand(target: ToolTarget, offset: Vector3, zoom: float) -> void:
	player.teleport_to(target.get_reach_point() + offset + Vector3.UP * 0.3)
	rig.set_zoom(zoom)
	rig.snap_to_target()
	for i in 40:
		await physics_frame
		if player.is_on_floor() and player.interaction.focused == target.interactable:
			break
	await _wait(10)


func _finish() -> void:
	for i in 900:
		if not user.is_busy():
			break
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	print(("  ok    " if condition else "  PROBLEM ") + label)
	if not condition:
		problems.append(label)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
