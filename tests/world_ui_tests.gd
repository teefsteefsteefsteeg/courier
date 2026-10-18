extends SceneTree
## World & UI automated checks (village, post office, forest entrance, NPC scenes,
## dialogue box, quest journal, location banner). Run headless from the project root:
##   godot --headless --path . --script res://tests/world_ui_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const CAST := {
	"PostmasterBram": ["Postmaster Bram", &"postmaster"],
	"MerchantMira": ["Merchant Mira", &"village_merchant"],
	"AlchemistCorvin": ["Alchemist Corvin", &"village_alchemist"],
	"MageElowen": ["Mage Elowen", &"forest_mage"],
	"VillagerPip": ["Villager Pip", &"villager_pip"],
}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var dialogue: DialogueBox
var journal: QuestJournal
var banner: LocationBanner
var prompt: InteractionPrompt


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == VILLAGE, "village is the main scene")
	_check(InputMap.has_action(&"toggle_journal") and InputHints.key_for(&"toggle_journal") == "J", "toggle_journal bound to J")

	level = (load(VILLAGE) as PackedScene).instantiate()
	# This suite covers World/UI on its own: drop the quest services so the journal's
	# preview data and fake-manager adapter can be exercised. The wired-up village is
	# covered by tests/village_quest_tests.gd.
	var services := level.get_node("GameplayServices")
	level.remove_child(services)
	services.free()
	root.add_child(level)
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	dialogue = level.get_node("DialogueBox")
	journal = level.get_node("QuestJournal")
	banner = level.get_node("LocationBanner")
	prompt = level.get_node("InteractionPrompt")
	await _frames(20)

	_test_world_structure()
	_test_npc_scenes()
	await _test_spawn_and_banner()
	await _test_walk_out_of_post_office()
	await _test_post_office_walls()
	await _test_forest_entrance()
	await _test_occlusion_fading()
	await _test_dialogue_with_npc()
	await _test_dialogue_walk_away()
	await _test_scripted_dialogue()
	await _test_journal_preview()
	await _test_journal_blocks_other_input()
	await _test_journal_hides_hud()
	await _test_journal_quest_manager_adapter()

	print("\n=== World/UI tests: %d passed, %d failed ===" % [_passes, _failures])
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
		await physics_frame


func _release_all() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"run"]:
		Input.action_release(action)


func _reset_player(at: Vector3) -> void:
	_release_all()
	player.teleport_to(at)
	rig.snap_to_target()


func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
	# Deliver now: two physics frames can elapse inside one main-loop iteration,
	# so waiting on frames alone does not guarantee the buffer was flushed.
	Input.flush_buffered_events()


func _walk(actions: Array, frames: int) -> void:
	for a in actions:
		Input.action_press(a)
	await _frames(frames)
	_release_all()
	await _frames(15)


# --- tests -------------------------------------------------------------------

func _test_world_structure() -> void:
	print("[World structure]")
	for path in ["PostOffice/Building", "PostOffice/Counter", "PostOffice/MailShelves", "PostOffice/SortingTable",
			"PostOffice/Mailbox", "PostOffice/Markers/QuestBoardSpot", "PostOffice/Markers/ParcelPickupSpot",
			"ForestEntrance/Gate", "ForestEntrance/StoneCircle", "ForestEntrance/Crystals",
			"ForestEntrance/Markers/ForestClearingSpot", "Props/Well", "Props/StallFruit", "Buildings/AlchemyShop",
			"Markers/MarketDeliverySpot", "Markers/AlchemyDeliverySpot"]:
		_check(level.has_node(path), "has %s" % path)
	var trees := level.get_node("ForestEntrance/Trees").get_child_count()
	_check(trees >= 30, "forest entrance is densely wooded (%d trees)" % trees)
	var shop := level.get_node("Buildings/AlchemyShop") as MedievalBuilding
	_check(shop != null and _roof_color(shop).is_equal_approx(shop.roof_color), "alchemy shop applies per-instance roof colour")
	var zones := get_nodes_in_group(LocationZone.GROUP)
	_check(zones.size() == 6, "six location zones registered (got %d)" % zones.size())


## Albedo of the first roof-tile surface override under a MedievalBuilding.
static func _roof_color(building: MedievalBuilding) -> Color:
	for node in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			if source != null and source.resource_name in MedievalBuilding.ROOF_MATERIALS:
				var override := mesh.get_surface_override_material(surface) as BaseMaterial3D
				return override.albedo_color if override != null else Color.BLACK
	return Color.BLACK


func _test_npc_scenes() -> void:
	print("[NPC scenes]")
	for node_name in CAST:
		var npc := level.get_node("NPCs/" + node_name) as NPC
		if npc == null:
			_check(false, "NPC %s exists" % node_name)
			continue
		var expected_name: String = CAST[node_name][0]
		_check(npc.npc_name == expected_name and npc.interactable.display_name == expected_name, "%s is named '%s'" % [node_name, npc.npc_name])
		_check(npc.npc_id == CAST[node_name][1], "%s has npc_id '%s'" % [node_name, CAST[node_name][1]])
		_check(npc.visual.get_child_count() > 3, "%s wears costume pieces (%d visual parts)" % [node_name, npc.visual.get_child_count()])
		var body := npc.body_mesh.material_override as StandardMaterial3D
		_check(body != null and body.albedo_color.is_equal_approx(npc.body_color), "%s body colour applied" % node_name)
		_check(npc.lines.size() >= 3, "%s has dialogue lines" % node_name)
	var pip := level.get_node("NPCs/VillagerPip") as NPC
	_check(is_equal_approx(pip.visual.scale.y, 0.85), "Pip's visual is child-sized")


func _test_spawn_and_banner() -> void:
	print("[Spawn & location banner]")
	await _frames(10)
	_check(player.is_on_floor(), "player spawns on the floor")
	_check(level.get_node("PostOffice/Zone").overlaps_body(player), "player spawns inside the post office")
	_check(banner.current_zone != null and banner.current_zone.display_name == "Willowmere Post Office",
			"banner announces the post office (got %s)" % (banner.current_zone.display_name if banner.current_zone else "none"))
	await _frames(30)
	_check(banner.banner.modulate.a > 0.5 and banner.title_label.text == "Willowmere Post Office", "banner is visible with the location name")
	_check(journal.hint_label.visible and journal.hint_label.text == "[J] Journal", "journal hint shown")
	_check(not dialogue.is_open() and not journal.is_open(), "dialogue and journal start closed")


func _test_walk_out_of_post_office() -> void:
	print("[Post office exit]")
	_reset_player(level.get_node("Markers/PlayerSpawn").global_position)
	await _frames(5)
	await _walk([&"move_back", &"move_right"], 150)  # S+D = world +X, out of the east door
	_check(player.global_position.x > -6.0, "player walks out the east door (x=%.2f)" % player.global_position.x)
	_check(banner.current_zone != null and banner.current_zone.display_name == "Willowmere Village",
			"banner switches to the village outside (got %s)" % (banner.current_zone.display_name if banner.current_zone else "none"))


func _test_post_office_walls() -> void:
	print("[Post office walls]")
	_reset_player(Vector3(-17, 0, -3))
	await _frames(5)
	await _walk([&"move_forward", &"move_left"], 90)  # W+A = world -X, into the west wall at x = -20
	_check(player.global_position.x > -19.6, "west wall blocks the player (x=%.2f)" % player.global_position.x)
	_reset_player(Vector3(-15, 0, -5.6))
	await _frames(5)
	await _walk([&"move_forward", &"move_right"], 90)  # W+D = world -Z, into the counter
	_check(player.global_position.z > -7.2, "counter blocks the player (z=%.2f)" % player.global_position.z)


func _test_forest_entrance() -> void:
	print("[Forest entrance]")
	_reset_player(Vector3(14, 0, -16.5))
	await _frames(5)
	await _walk([&"move_forward", &"move_right"], 140)  # world -Z through the gate
	_check(player.global_position.z < -26.0, "player passes through the Whisperwood gate (z=%.2f)" % player.global_position.z)
	_check(banner.current_zone != null and banner.current_zone.display_name == "Whisperwood Edge",
			"banner announces Whisperwood Edge (got %s)" % (banner.current_zone.display_name if banner.current_zone else "none"))
	_reset_player(Vector3(14, 0, -30.4))
	await _frames(8)
	_check(banner.current_zone != null and banner.current_zone.display_name == "Moonstone Clearing", "nested clearing zone takes priority")


func _test_occlusion_fading() -> void:
	print("[Occlusion fading]")
	var occluders := get_nodes_in_group(CameraOccluder.GROUP)
	_check(occluders.size() > 100, "trees and cottages register as occluders (%d)" % occluders.size())
	_reset_player(Vector3(15.4, 0, -30.9))  # in the clearing, behind the camera-side tree wall
	await create_timer(0.6).timeout  # fades run on real time
	var faded: Array[CameraOccluder] = []
	for node in occluders:
		if (node as CameraOccluder).occluding:
			faded.append(node)
	_check(not faded.is_empty(), "trees between camera and player are flagged (%d)" % faded.size())
	if not faded.is_empty():
		var mesh := faded[0].get_parent().find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D
		_check(faded[0].get_fade_amount() > 0.99 and mesh.transparency > 0.6, "flagged tree fades out (transparency %.2f)" % mesh.transparency)
	var far_tree := level.get_node("Trees/Tree01").get_node("CameraOccluder") as CameraOccluder
	_check(not far_tree.occluding and far_tree.get_fade_amount() == 0.0, "trees elsewhere stay opaque")
	_reset_player(Vector3(-2, 0, -2))
	await create_timer(0.6).timeout
	var still_faded := faded.filter(func(o: CameraOccluder) -> bool: return o.occluding or o.get_fade_amount() > 0.0)
	_check(still_faded.is_empty(), "trees fade back in once the player leaves")


func _test_dialogue_with_npc() -> void:
	print("[Dialogue box: NPC conversation]")
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	_reset_player(Vector3(-15, 0, -6.8))
	await _frames(6)
	_check(player.interaction.focused == bram.interactable, "player focuses Postmaster Bram across the counter")
	_check(prompt.panel.visible, "interaction prompt visible before talking")

	var before := bram.interaction_count
	_press(&"interact")
	await _frames(2)
	_check(dialogue.is_open() and dialogue.name_label.text == "Postmaster Bram", "dialogue opens with Bram's name plate")
	_check(dialogue.get_text() == bram.lines[0], "shows Bram's first line")
	_check(dialogue.is_typing() and dialogue.text_label.visible_characters < dialogue.get_text().length(), "text types out progressively")
	_check(not bram.speech_label.visible, "world speech bubble hidden while the box shows the line")
	_check(not prompt.panel.visible, "interaction prompt suppressed during dialogue")
	_check(dialogue.portrait_initial.text == "B", "portrait shows speaker initial")

	_press(&"interact")
	await _frames(2)
	_check(not dialogue.is_typing() and dialogue.text_label.visible_characters == -1, "interact while typing completes the line")
	_check(bram.interaction_count == before + 1, "skip press is consumed (NPC not re-triggered)")
	_check(dialogue.hint_label.text.begins_with("[E] Talk"), "hint offers to keep talking ('%s')" % dialogue.hint_label.text)

	_press(&"interact")
	await _frames(2)
	_check(bram.interaction_count == before + 2 and dialogue.get_text() == bram.lines[1], "interact after the line asks the NPC for the next line (count +%d, text=%s, typing=%s, focus=%s)" % [bram.interaction_count - before, dialogue.get_text(), dialogue.is_typing(), player.interaction.focused])
	# Typewriter runs on real time (_process delta), so wait in seconds, not frames.
	var budget := float(dialogue.get_text().length()) / dialogue.characters_per_second + 0.5
	await create_timer(budget).timeout
	_check(not dialogue.is_typing(), "typewriter finishes on its own within %.1f s" % budget)

	_press(&"ui_cancel")
	await _frames(2)
	_check(not dialogue.is_open(), "Escape closes the dialogue")
	_check(prompt.panel.visible, "prompt returns after dialogue closes")


func _test_dialogue_walk_away() -> void:
	print("[Dialogue box: walking away]")
	_reset_player(Vector3(-15, 0, -6.8))
	await _frames(5)
	_press(&"interact")
	await _frames(2)
	_check(dialogue.is_open(), "dialogue open again")
	_reset_player(Vector3(-15, 0, 0))
	await _frames(6)
	_check(not dialogue.is_open(), "leaving interaction range closes the dialogue")


func _test_scripted_dialogue() -> void:
	print("[Dialogue box: scripted lines]")
	_reset_player(Vector3(0, 0, 8))
	await _frames(5)
	var started: Array[String] = []
	var on_line := func(_speaker: String, text: String) -> void: started.append(text)
	dialogue.line_started.connect(on_line)
	var closed_count := [0]
	var on_closed := func() -> void: closed_count[0] += 1
	dialogue.closed.connect(on_closed)

	dialogue.play_lines("Narrator", PackedStringArray(["One.", "Two.", "Three."]))
	await _frames(2)
	_check(dialogue.is_open() and dialogue.get_queued_count() == 2, "scripted sequence queued")
	for i in 3:
		dialogue.skip_typing()
		_press(&"ui_accept")
		await _frames(2)
	_check(started == ["One.", "Two.", "Three."], "lines played in order (%s)" % [started])
	_check(not dialogue.is_open() and closed_count[0] == 1, "accept on the last line closes once")
	dialogue.line_started.disconnect(on_line)
	dialogue.closed.disconnect(on_closed)


func _test_journal_preview() -> void:
	print("[Quest journal: preview data]")
	_check(not journal.use_sample_data_when_unconnected, "village journal does not fall back to preview entries")
	journal.use_sample_data_when_unconnected = true
	_reset_player(Vector3(0, 0, 8))
	await _frames(3)
	_press(&"toggle_journal")
	await _frames(2)
	_check(journal.is_open(), "J opens the journal")
	_check(journal.is_in_group(QuestJournal.MODAL_GROUP), "open journal is modal")
	_check(not player.input_enabled, "player input paused while journal open")
	_check(journal.source_label.visible, "preview-data notice shown without a quest system")
	_check(journal.tab_active.text == "In Progress (2)" and journal.tab_archive.text == "Archive (2)",
			"tab counts (%s / %s)" % [journal.tab_active.text, journal.tab_archive.text])
	_check(journal.quest_list.get_child_count() == 2, "two deliveries listed in progress")
	_check(journal.detail_title.text == "First Delivery", "first entry selected by default")
	_check(journal.route_label.text == "From Postmaster Bram  ·  To Merchant Mira, Village Market", "route line ('%s')" % journal.route_label.text)
	var rows := journal.objectives_box.get_children()
	_check(rows.size() == 3, "three objectives shown")
	if rows.size() == 3:
		_check(rows[0].get_meta(&"done") and rows[1].get_meta(&"done") and not rows[2].get_meta(&"done"), "objective completion marks")
		_check(rows[2].get_meta(&"current"), "current objective highlighted")
	_check(journal.reward_label.visible and journal.reward_label.text == "Reward: 15 Gold, 5 Reputation", "reward shown")

	(journal.quest_list.get_child(1) as Button).pressed.emit()
	await _frames(1)
	_check(journal.get_selected_id() == &"sample_dragon_egg" and journal.detail_title.text == "The Dragon Egg", "clicking an entry shows its details")

	journal.tab_archive.pressed.emit()
	await _frames(1)
	_check(journal.current_tab == QuestJournal.Tab.ARCHIVE and journal.quest_list.get_child_count() == 2, "archive tab lists finished deliveries")
	journal.select_entry(&"sample_potion")
	_check(journal.status_label.text == "FAILED", "failed delivery marked FAILED")
	journal.show_tab(QuestJournal.Tab.IN_PROGRESS)

	var start := player.global_position
	Input.action_press(&"move_forward")
	await _frames(20)
	_release_all()
	_check(player.global_position.distance_to(start) < 0.01, "player does not move while journal is open")

	_press(&"ui_cancel")
	await _frames(2)
	_check(not journal.is_open() and player.input_enabled, "Escape closes the journal and restores input")
	_press(&"toggle_journal")
	await _frames(2)
	_press(&"toggle_journal")
	await _frames(2)
	_check(not journal.is_open(), "J toggles the journal closed")


func _test_journal_blocks_other_input() -> void:
	print("[Quest journal: modal]")
	journal.open()
	dialogue.show_line("Tester", "Hello.")
	dialogue.skip_typing()
	_press(&"ui_accept")
	await _frames(2)
	_check(dialogue.is_open(), "dialogue ignores input while the journal is open")
	journal.close()
	_press(&"ui_accept")
	await _frames(2)
	_check(not dialogue.is_open(), "dialogue responds again once the journal closes")


func _test_journal_hides_hud() -> void:
	print("[Quest journal: hides prompt and banner]")
	var bram := level.get_node("NPCs/PostmasterBram") as NPC
	_reset_player(Vector3(-15, 0, -6.8))
	await _frames(6)
	banner.show_location("Willowmere Post Office")
	await create_timer(banner.fade_in_time + 0.1).timeout
	_check(prompt.visible and prompt.panel.visible and banner.visible and banner.banner.modulate.a > 0.5,
			"prompt and banner on screen before opening the journal")

	_press(&"toggle_journal")
	await _frames(2)
	_check(journal.is_open() and not prompt.visible and not banner.visible, "open journal hides the prompt and banner layers")
	_check(not prompt.panel.visible, "prompt panel also stands down while a modal is open")
	_press(&"toggle_journal")
	await _frames(2)
	_check(not journal.is_open() and prompt.visible and banner.visible, "closing the journal restores the prompt and banner")
	_check(prompt.panel.visible and player.input_enabled, "prompt shown again and player input restored")

	banner.visible = false
	journal.open()
	_check(not prompt.visible and not banner.visible, "both hidden while open")
	journal.close()
	_check(prompt.visible and not banner.visible, "a layer hidden before opening stays hidden after closing")
	banner.visible = true

	var before := bram.interaction_count
	_press(&"interact")
	await _frames(2)
	_check(dialogue.is_open() and bram.interaction_count == before + 1 and not prompt.panel.visible, "dialogue opens and suppresses the prompt")
	journal.open()
	_check(not prompt.visible and not banner.visible, "journal over dialogue hides the HUD")
	_press(&"interact")
	await _frames(2)
	_check(bram.interaction_count == before + 1 and dialogue.is_open(), "interact is ignored while the journal is open")
	_press(&"ui_cancel")
	await _frames(2)
	_check(not journal.is_open() and dialogue.is_open(), "Escape closes only the journal")
	_check(prompt.visible and not prompt.panel.visible, "prompt layer restored but still suppressed by dialogue")
	_press(&"ui_cancel")
	await _frames(2)
	_check(not dialogue.is_open() and prompt.panel.visible, "closing the dialogue brings the prompt back")


func _test_journal_quest_manager_adapter() -> void:
	print("[Quest journal: QuestManager adapter]")
	var manager := _make_fake_quest_manager()
	level.add_child(manager)
	await _frames(1)
	journal.open()
	_check(not journal.source_label.visible, "preview notice hidden once a quest manager exists")
	_check(journal.entries.size() == 2, "AVAILABLE quests are not journaled (%d entries)" % journal.entries.size())
	var active := journal.get_visible_entries()
	_check(active.size() == 1 and active[0]["title"] == "Fake Parcel", "ACTIVE quest listed in progress")
	_check(journal.route_label.text == "From Postmaster Bram  ·  To Merchant Mira, Village Market", "giver id resolved to NPC name ('%s')" % journal.route_label.text)
	var rows := journal.objectives_box.get_children()
	_check(rows.size() == 2 and rows[0].get_meta(&"done") and rows[1].get_meta(&"current"), "objective index mapped to done/current")
	_check(journal.reward_label.text == "Reward: 10 Gold", "reward via describe()")
	journal.show_tab(QuestJournal.Tab.ARCHIVE)
	_check(journal.get_visible_entries().size() == 1 and journal.status_label.text == "DELIVERED", "REWARDED quest archived as delivered")

	manager.call(&"complete_first")
	await _frames(3)
	_check(journal.tab_archive.text == "Archive (2)", "journal refreshes on quest_state_changed (%s)" % journal.tab_archive.text)
	journal.close()
	manager.queue_free()


## Minimal stand-in that mirrors the gameplay QuestManager's public surface.
func _make_fake_quest_manager() -> Node:
	var state_script := GDScript.new()
	state_script.source_code = """extends RefCounted
enum Status { AVAILABLE, ACCEPTED, ACTIVE, COMPLETED, FAILED, REWARDED }
var status: int = Status.AVAILABLE
var objective_index: int = 0
var objective_progress := PackedInt32Array()
var fail_reason := ""
"""
	state_script.reload()
	var thing_script := GDScript.new()
	thing_script.source_code = """extends RefCounted
var title := ""
var description := ""
var giver_id: StringName
var recipient_name := ""
var destination_name := ""
var objectives: Array = []
var reward: RefCounted
var required_count := 1
var gold := 0
func describe() -> String:
	return "%d Gold" % gold
"""
	thing_script.reload()
	var manager_script := GDScript.new()
	manager_script.source_code = """extends Node
signal quest_state_changed(quest_id: StringName, new_status: int, old_status: int)
var defs := {}
var states := {}
func _enter_tree() -> void:
	add_to_group(&"quest_manager")
func get_quest_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(defs.keys())
	return ids
func get_definition(id: StringName) -> Object:
	return defs.get(id)
func get_state(id: StringName) -> Object:
	return states.get(id)
func complete_first() -> void:
	states[&"q_fake"].status = 5
	quest_state_changed.emit(&"q_fake", 5, 2)
"""
	manager_script.reload()
	var manager: Node = manager_script.new()
	var specs := [
		[&"q_fake", "Fake Parcel", 2, 1],  # ACTIVE, on objective 1
		[&"q_done", "Old Letter", 5, 2],  # REWARDED
		[&"q_open", "Board Posting", 0, 0],  # AVAILABLE
	]
	for spec in specs:
		var definition: RefCounted = thing_script.new()
		definition.title = spec[1]
		definition.description = "Test quest."
		definition.giver_id = &"postmaster"
		definition.recipient_name = "Merchant Mira"
		definition.destination_name = "Village Market"
		for text in ["Pick up", "Deliver"]:
			var objective: RefCounted = thing_script.new()
			objective.description = text
			definition.objectives.append(objective)
		definition.reward = thing_script.new()
		definition.reward.gold = 10
		var state: RefCounted = state_script.new()
		state.status = spec[2]
		state.objective_index = spec[3]
		state.objective_progress = PackedInt32Array([1, 0])
		manager.defs[spec[0]] = definition
		manager.states[spec[0]] = state
	return manager
