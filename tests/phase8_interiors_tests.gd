extends SceneTree
## Phase 8 milestone 5: enterable houses with NPCs, in the real village with real keys.
## - Three doors (Armory -> Brenna's Forge, Post Office -> Courier Guild Hall, Rose Cottage),
##   each "[E] Enter ..." into its own interior region; "[E] Leave" puts the courier back
##   outside the same door. Gold, items, levels and a carried package come along.
## - Inside: the village is paused and hidden, no minimap or world map; the room keeps the
##   courier in; nothing taller than the low wall on the camera's side (no clipping).
## - NPCs and purpose: Torvin enhances gear (gold + ore), Ivy gives "The Sealed Letter"
##   (talk, pick up the letter on her desk), Granny Hollis receives it (reward) and lends her
##   bed (full heal; refused at full health). NPCs turn to face the courier.
## - A knockout indoors returns the courier outside the door.
##   godot --headless --path . --script res://tests/phase8_interiors_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const DOORS := {
	"ArmoryDoor": [&"interior_armory", "ArmoryForge"],
	"GuildHallDoor": [&"interior_guild_hall", "GuildHall"],
	"RoseCottageDoor": [&"interior_rose_cottage", "RoseCottage"],
}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var router: Node
var inventory: CourierInventory
var wallet: CourierWallet
var quests: QuestManager
var health: CombatHealth


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_interiors_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	router = get_first_node_in_group(&"phase6_router")
	inventory = CourierInventory.find(self)
	wallet = CourierWallet.find(self)
	quests = QuestManager.find(self)
	health = CombatController.find_on(player).health
	await _frames(20)
	wallet.add_gold(1000)
	inventory.add_item(inventory.get_definition(&"iron_sword"))
	inventory.equip(&"iron_sword")
	inventory.set_enhancement(&"iron_sword", 2)
	inventory.add_material(inventory.get_material_definition(&"iron_ore"), 10)

	await _test_doors()
	await _test_rooms()
	await _test_sealed_letter()
	await _test_forge_and_bed()
	await _test_knockout_inside()

	print("\n=== Phase 8 interiors tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -----------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


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


func _door(door_name: String) -> HouseDoor:
	return level.get_node("HouseDoors/" + door_name) as HouseDoor


func _room() -> InteriorRoom:
	return router.get(&"active_level") as InteriorRoom


func _wait_region(region: StringName) -> void:
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == region and not router.get(&"crossing"):
			break
	await _frames(3)


func _stand_by(target: Node3D, offset: Vector3) -> void:
	player.teleport_to(target.global_position + offset + Vector3.UP * 0.2)
	await _physics(20)


## Goes in through a door with the real E key.
func _enter(door_name: String) -> bool:
	var door := _door(door_name)
	await _stand_by(door, door.get_exit_point() - door.global_position)
	for i in 30:
		if player.interaction.focused == door.interactable:
			break
		await physics_frame
	await _key(KEY_E)
	await _wait_region(DOORS[door_name][0])
	return router.get(&"region_id") == DOORS[door_name][0]


func _leave() -> void:
	var room := _room()
	var exit := room.get_node(room.exit_interactable) as Interactable
	await _stand_by(exit.get_parent() as Node3D, Vector3(0, 0, 0.6))
	await _key(KEY_E)
	await _wait_region(&"village")


## Stands 1.2 m from npc on the side of the room's centre (clear of furniture) and presses E.
func _talk(npc: Node3D) -> void:
	var toward := (_room().global_position - npc.global_position) * Vector3(1, 0, 1)
	await _stand_by(npc, toward.normalized() * 1.2 if toward.length() > 0.1 else Vector3(0, 0, 1.2))
	for i in 20:
		if player.interaction.focused != null and player.interaction.focused.get_parent() == npc:
			break
		await physics_frame
	await _key(KEY_E)
	await _frames(5)


func _close_dialogue() -> void:
	for i in 8:
		if get_node_count_in_group(DialogueBox.OPEN_GROUP) == 0:
			break
		await _key(KEY_E)
		await _frames(4)


# --- tests -------------------------------------------------------------------

func _test_doors() -> void:
	print("[Doors in and out]")
	var space := player.get_world_3d().direct_space_state
	for door_name in DOORS:
		var door := _door(door_name)
		_check(door != null and door.interior_id == DOORS[door_name][0] and door.interactable != null, "%s leads to %s" % [door_name, DOORS[door_name][0]])
		var query := PhysicsPointQueryParameters3D.new()
		query.position = door.get_exit_point() + Vector3.UP * 0.6
		query.collision_mask = 1
		_check(space.intersect_point(query).is_empty(), "%s: the doorstep is outside every wall" % door_name)
	var package_count := inventory.get_material_count(&"iron_ore")
	for door_name in DOORS:
		var gold := wallet.gold
		var inside := await _enter(door_name)
		_check(inside, "%s: E goes inside" % door_name)
		if not inside:
			continue
		var room := _room()
		_check(room != null and room.name == DOORS[door_name][1], "%s: the %s interior is loaded" % [door_name, DOORS[door_name][1]])
		var entry := room.get_node("Spawns/Entry") as Node3D
		_check(player.global_position.distance_to(entry.global_position) < 0.6, "%s: the courier stands at the entry" % door_name)
		_check(not (level.get_node("Buildings") as Node3D).visible and not level.get_node("Buildings").can_process(), "%s: the village is hidden and paused" % door_name)
		var minimap := level.get_node("GameplayHUD/Minimap")
		_check(not (minimap.get(&"compact") as Control).visible, "%s: no minimap indoors" % door_name)
		await _key(KEY_M)
		_check(not minimap.call(&"is_expanded"), "%s: M opens no world map indoors" % door_name)
		_check(wallet.gold == gold and inventory.get_enhancement(&"iron_sword") == 2 and inventory.get_material_count(&"iron_ore") == package_count and inventory.is_equipped(&"iron_sword"), "%s: gold, items and levels come along" % door_name)
		await _leave()
		var distance := player.global_position.distance_to(_door(door_name).get_exit_point())
		_check(router.get(&"region_id") == &"village" and distance < 0.6, "%s: E at the exit returns to the same door (%.2f m)" % [door_name, distance])
		_check((level.get_node("Buildings") as Node3D).visible and (minimap.get(&"compact") as Control).visible, "%s: the village and minimap are back" % door_name)


func _test_rooms() -> void:
	print("[Rooms]")
	for door_name in DOORS:
		await _enter(door_name)
		var room := _room()
		# Walk into the camera-side walls for two seconds: the courier stays inside.
		player.teleport_to(room.get_node("Spawns/Entry").global_position)
		Input.action_press(&"move_back")
		Input.action_press(&"move_right")
		await _physics(120)
		Input.action_release(&"move_back")
		Input.action_release(&"move_right")
		var floor_box := (room.get_node("RoomCollision/Floor") as CollisionShape3D)
		var half := ((floor_box.shape as BoxShape3D).size * 0.5)
		var local := room.to_local(player.global_position)
		_check(absf(local.x) < half.x and absf(local.z) < half.z and player.global_position.y > -0.5, "%s: walking into the walls keeps the courier in (%.1f, %.1f)" % [door_name, local.x, local.z])
		# Cut-away: nothing on the camera's side (south and east edges) is above the low wall.
		var tall: Array[String] = []
		for mesh: MeshInstance3D in room.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			var edge := room.to_local(box.get_center())
			if (edge.z > half.z - 0.6 or edge.x > half.x - 0.6) and box.end.y > InteriorRoomTestHelper.LOW_LIMIT:
				tall.append(String(mesh.name))
		_check(tall.is_empty(), "%s: nothing tall blocks the camera (%s)" % [door_name, tall])
		var npcs := room.find_children("*", "NPC", true, false)
		_check(npcs.size() == 1, "%s: one NPC lives here (%s)" % [door_name, npcs.map(func(n: Node) -> String: return String(n.name))])
		var lights := room.find_children("*", "OmniLight3D", true, false).size()
		_check(lights >= 1 and room.get_node_or_null("WorldEnvironment") != null, "%s: lit, with its own environment" % door_name)
		await _leave()


func _test_sealed_letter() -> void:
	print("[The Sealed Letter: Ivy -> Granny Hollis]")
	_check(quests.accept_quest(&"q004_sealed_letter") == QuestManager.AcceptResult.OK, "the board offers and accepts the contract")
	await _enter("GuildHallDoor")
	var ivy := _room().find_child("GuildClerkIvy", true, false) as Node3D
	var facing_before := ivy.global_basis.z
	await _talk(ivy)
	_check(quests.get_state(&"q004_sealed_letter").objective_index == 1, "talking to Ivy completes the first step")
	var to_player := (player.global_position - ivy.global_position) * Vector3(1, 0, 1)
	await _physics(30)
	_check(ivy.find_child("Visual", false, false) != null and (ivy.get_node("Visual") as Node3D).global_basis.z.dot(to_player.normalized()) > 0.7 or ivy.global_basis.z.dot(to_player.normalized()) > 0.7, "Ivy turns to face the courier")
	await _close_dialogue()
	var letter := _room().get_node("SealedLetterPickup") as Node3D
	await _stand_by(letter, Vector3(0, 0, 0.9))
	await _key(KEY_E)
	await _frames(4)
	var carrier := PackageCarrier.find_on(player)
	_check(carrier.get_package() != null and carrier.get_package().definition.package_id == &"pkg_sealed_letter", "E takes the Sealed Letter from Ivy's desk")
	await _leave()
	_check(carrier.get_package() != null, "the letter is still carried outside")
	var gold := wallet.gold
	await _enter("RoseCottageDoor")
	var granny := _room().find_child("GrannyHollis", true, false) as Node3D
	await _talk(granny)
	_check(quests.get_status(&"q004_sealed_letter") == QuestState.Status.REWARDED and wallet.gold == gold + 70 and carrier.get_package() == null, "Granny Hollis takes the letter: +70 gold (%d)" % (wallet.gold - gold))
	await _close_dialogue()
	await _leave()


func _test_forge_and_bed() -> void:
	print("[Torvin's forge and Granny's bed]")
	var entered := await _enter("ArmoryDoor")
	var torvin := _room().find_child("ForgemasterTorvin", true, false) as Node3D if entered else null
	_check(torvin != null, "Torvin is in the forge (entered: %s, region %s)" % [entered, router.get(&"region_id")])
	if torvin == null:
		return
	await _talk(torvin)
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	_check(shop.is_open() and shop.rows.is_empty() and shop.enhance_rows.has(&"iron_sword"), "E at Torvin opens the forge: enhancing only")
	var gold := wallet.gold
	var ore := inventory.get_material_count(&"iron_ore")
	shop.enhance_item(&"iron_sword")
	_check(inventory.get_enhancement(&"iron_sword") == 3 and wallet.gold == gold - Enhancement.gold_cost(2) and inventory.get_material_count(&"iron_ore") == ore - Enhancement.ore_cost(2), "Torvin raises the sword to +3 for 180 gold and 3 ore")
	shop.close()
	await _frames(4)
	await _leave()
	await _enter("RoseCottageDoor")
	var bed := _room().get_node("RestBed") as RestBed
	health.apply_damage(45.0, Vector3.ZERO)
	await _stand_by(bed, Vector3(0.3, 0, 0.5))
	_check(player.interaction.focused == bed.interactable, "the bed can be reached")
	await _key(KEY_E)
	_check(is_equal_approx(health.get_health(), health.get_max_health()), "resting restores full health")
	_check(is_zero_approx(bed.rest(player)), "at full health the bed does nothing")
	await _leave()


func _test_knockout_inside() -> void:
	print("[Knocked out indoors]")
	await _enter("GuildHallDoor")
	health.apply_damage(health.get_health() + 10.0, Vector3.ZERO)
	for i in 200:
		await physics_frame
		if router.get(&"region_id") == &"village" and not router.get(&"crossing"):
			break
	await _physics(10)
	var distance := player.global_position.distance_to(_door("GuildHallDoor").get_exit_point())
	_check(router.get(&"region_id") == &"village" and not health.is_dead() and distance < 1.0, "a knockout inside sends the courier back out of the door (%.2f m)" % distance)


class InteriorRoomTestHelper:
	## Height (m) nothing near the camera-side walls may exceed.
	const LOW_LIMIT := 1.05
