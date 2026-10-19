extends SceneTree
## Renders Phase 8 milestone 5 (enterable houses) in the real village (GPU window, NOT
## --headless), all with the real E key: each door from outside, the room inside, its NPC
## talking (facing the courier), its service (Torvin's forge, the Sealed Letter contract at
## Ivy's desk and its delivery to Granny Hollis, her bed), and the courier back outside the
## same door. SaveGame is removed and UISettings does not persist.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase8_interiors.gd -- <output_dir>

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var router: Node
var out_dir: String
var problems: PackedStringArray = []
var shot_index := 33


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
	router = get_first_node_in_group(&"phase6_router")
	await _seconds(1.0)
	var inventory := CourierInventory.find(self)
	var wallet := CourierWallet.find(self)
	wallet.add_gold(500)
	inventory.add_item(inventory.get_definition(&"iron_sword"))
	inventory.equip(&"iron_sword")
	inventory.add_material(inventory.get_material_definition(&"iron_ore"), 5)
	var quests := QuestManager.find(self)

	# Courier Guild hall: accept the Sealed Letter, talk to Ivy, take the letter.
	quests.accept_quest(&"q004_sealed_letter")
	await _enter("GuildHallDoor", "the Courier Guild Hall")
	var ivy := _npc("GuildClerkIvy")
	await _walk_to(ivy, Vector3(0.0, 0, 1.3))
	await _key(KEY_E)
	await _seconds(0.6)
	await _shot("guild_hall_talk_to_ivy")
	await _close_dialogue()
	var letter := (router.get(&"active_level") as Node).get_node("SealedLetterPickup") as Node3D
	await _walk_to(letter, Vector3(0, 0, 0.9))
	await _key(KEY_E)
	await _seconds(0.4)
	var carrier := PackageCarrier.find_on(player)
	_expect(carrier.get_package() != null and carrier.get_package().definition.package_id == &"pkg_sealed_letter", "picked up the Sealed Letter")
	await _leave("GuildHallDoor")

	# Rose Cottage: deliver the letter, rest in the bed.
	await _enter("RoseCottageDoor", "Rose Cottage")
	var granny := _npc("GrannyHollis")
	await _walk_to(granny, Vector3(0.6, 0, 1.2))
	await _key(KEY_E)
	await _seconds(0.6)
	_expect(quests.get_status(&"q004_sealed_letter") == QuestState.Status.REWARDED or quests.get_status(&"q004_sealed_letter") == QuestState.Status.COMPLETED, "the letter was delivered (%s)" % quests.get_status(&"q004_sealed_letter"))
	await _shot("rose_cottage_letter_delivered")
	await _close_dialogue()
	var health := CombatController.find_on(player).health
	health.apply_damage(40.0, Vector3.ZERO)
	var bed := (router.get(&"active_level") as Node).get_node("RestBed") as Node3D
	await _walk_to(bed, Vector3(0.4, 0, 0.6))
	await _key(KEY_E)
	await _seconds(0.5)
	_expect(is_equal_approx(health.get_health(), health.get_max_health()), "resting restored health (%.0f)" % health.get_health())
	await _shot("rose_cottage_rested")
	await _leave("RoseCottageDoor")

	# Armory: Torvin's forge.
	await _enter("ArmoryDoor", "Brenna's Forge")
	var torvin := _npc("ForgemasterTorvin")
	await _walk_to(torvin, Vector3(0.9, 0, 1.0))
	await _key(KEY_E)
	await _seconds(0.6)
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	_expect(shop.is_open() and shop.enhance_rows.has(&"iron_sword"), "Torvin opens the forge's Enhance section")
	await _shot("armory_forge_torvin")
	shop.close()
	await _seconds(0.3)
	await _leave("ArmoryDoor")
	print("CAPTURE problems: %d %s" % [problems.size(), problems])
	quit(problems.size())


func _npc(node_name: String) -> Node3D:
	return (router.get(&"active_level") as Node).find_child(node_name, true, false) as Node3D


func _enter(door_name: String, place: String) -> void:
	var door := level.get_node("HouseDoors/" + door_name) as HouseDoor
	player.teleport_to(door.get_exit_point() + Vector3.UP * 0.2)
	rig.set_zoom(10.0)
	rig.snap_to_target()
	for i in 40:
		await physics_frame
		if player.interaction.focused == door.interactable:
			break
	await _seconds(0.3)
	await _shot("%s_outside" % door_name.to_snake_case())
	_expect(player.interaction.focused == door.interactable, "%s: E focuses the door (%s)" % [door_name, player.interaction.focused])
	await _key(KEY_E)
	for i in 90:
		await physics_frame
		if router.get(&"region_id") == door.interior_id and not router.get(&"crossing"):
			break
	await _seconds(0.6)
	_expect(router.get(&"region_id") == door.interior_id, "%s: inside %s" % [door_name, place])
	await _shot("%s_inside" % door_name.to_snake_case())


func _leave(door_name: String) -> void:
	var door := level.get_node("HouseDoors/" + door_name) as HouseDoor
	var room := router.get(&"active_level") as InteriorRoom
	var exit := room.get_node(room.exit_interactable) as Interactable
	await _walk_to(exit.get_parent() as Node3D, Vector3(0, 0, 0.5))
	_expect(player.interaction.focused == exit, "%s: the exit door is in reach" % door_name)
	await _key(KEY_E)
	for i in 90:
		await physics_frame
		if router.get(&"region_id") == &"village" and not router.get(&"crossing"):
			break
	await _seconds(0.5)
	var distance := player.global_position.distance_to(door.get_exit_point())
	_expect(router.get(&"region_id") == &"village" and distance < 0.6, "%s: back outside the same door (%.2f m away)" % [door_name, distance])
	await _shot("%s_back_outside" % door_name.to_snake_case())


func _walk_to(target: Node3D, offset: Vector3) -> void:
	player.teleport_to(target.global_position + offset + Vector3.UP * 0.2)
	rig.snap_to_target()
	await _seconds(0.4)


func _close_dialogue() -> void:
	for i in 6:
		if get_node_count_in_group(DialogueBox.OPEN_GROUP) == 0:
			break
		await _key(KEY_E)
		await _seconds(0.2)


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
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%d_%s.png" % [shot_index, name])
	shot_index += 1
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
