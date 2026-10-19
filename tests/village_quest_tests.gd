extends SceneTree
## Village ↔ quest system integration: gameplay services, quest board, package pickups,
## destination and quest NPCs placed in the real village, plus the shared modal rules
## between the board window, interaction prompt, dialogue box and journal.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/village_quest_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const S := QuestState.Status
const Q1 := &"q001_first_delivery"
const Q2 := &"q002_dragon_egg"
const Q3 := &"q003_unstable_potion"
const QUEST_NPCS := ["PostmasterBram", "MerchantMira", "AlchemistCorvin", "MageElowen"]
const PICKUPS := "PostOffice/Markers/ParcelPickupSpot/"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var manager: QuestManager
var wallet: CourierWallet
var carrier: PackageCarrier
var board: QuestBoard
var board_ui: QuestBoardUI
var hud: GameplayHUD
var prompt: InteractionPrompt
var dialogue: DialogueBox
var journal: QuestJournal
var banner: LocationBanner


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	manager = QuestManager.find(self)
	wallet = CourierWallet.find(self)
	carrier = PackageCarrier.find_on(player)
	board = level.get_node("PostOffice/Markers/QuestBoardSpot/QuestBoard")
	board_ui = level.get_node("QuestBoardUI")
	hud = level.get_node("GameplayHUD")
	prompt = level.get_node("InteractionPrompt")
	dialogue = level.get_node("DialogueBox")
	journal = level.get_node("QuestJournal")
	banner = level.get_node("LocationBanner")
	await _frames(20)

	_test_services()
	_test_placement()
	_test_quest_data_resolves()
	_test_hud_layout()
	await _test_board_window_is_modal()
	await _test_q1_first_delivery()
	await _test_q2_dragon_egg()
	await _test_q3_potion_crate()

	print("\n=== Village quest tests: %d passed, %d failed ===" % [_passes, _failures])
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
	await process_frame


func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _status(id: StringName) -> String:
	return QuestState.status_name(manager.get_status(id))


## Puts the player `distance` metres from `target`, on the side facing `toward`.
func _stand_near(target: Node3D, toward: Vector3, distance: float = 1.2) -> void:
	var offset := toward - target.global_position
	offset.y = 0.0
	player.teleport_to(target.global_position + offset.normalized() * distance)
	rig.snap_to_target()
	await _frames(6)


## Walks up to an interactable, checks it has focus, and presses E.
func _interact_with(target: Node3D, interactable: Interactable, toward: Vector3, label: String, distance: float = 1.2) -> void:
	await _stand_near(target, toward, distance)
	_check(player.interaction.focused == interactable, "player focuses %s" % label)
	_press(&"interact")
	await _frames(2)


func _npc(node_name: String) -> NPC:
	return level.get_node("NPCs/" + node_name) as NPC


func _pickup_for(package_id: StringName) -> PackagePickup:
	for node in level.get_node("PostOffice/Markers/ParcelPickupSpot").get_children():
		var pickup := node as PackagePickup
		if pickup != null and pickup.package_definition.package_id == package_id:
			return pickup
	return null


func _accept_on_board(quest_id: StringName) -> void:
	await _interact_with(board, board.interactable, board.global_position + Vector3(0, 0, 2), "the quest board")
	_check(board_ui.is_open(), "E opens the board window")
	var button: Button = board_ui.accept_buttons.get(quest_id)
	_check(button != null and button.visible and not button.disabled, "%s can be accepted" % quest_id)
	if button != null:
		button.pressed.emit()
	await _frames(1)
	_check(manager.get_status(quest_id) == S.ACCEPTED, "%s accepted (%s)" % [quest_id, _status(quest_id)])
	_press(&"ui_cancel")
	await _frames(2)
	_check(not board_ui.is_open() and player.input_enabled, "Escape closes the board and restores input")


func _pick_up(package_id: StringName) -> void:
	var pickup := _pickup_for(package_id)
	_check(pickup != null and pickup.is_available() and pickup.visible, "%s pickup appears at the post office" % package_id)
	if pickup == null:
		return
	await _interact_with(pickup, pickup.interactable, pickup.global_position + Vector3(0, 0, 1), String(package_id))
	_check(carrier.is_carrying() and carrier.get_package().definition.package_id == package_id, "player carries %s" % package_id)
	_check(not pickup.visible, "pickup hidden once taken")


func _deliver_to(npc: NPC, stand_toward: Vector3, quest_id: StringName) -> void:
	var gold_before := wallet.gold
	await _interact_with(npc, npc.interactable, stand_toward, npc.npc_name)
	var definition := manager.get_definition(quest_id)
	_check(manager.get_status(quest_id) == S.REWARDED, "%s rewarded after delivering to %s (%s)" % [quest_id, npc.npc_name, _status(quest_id)])
	_check(not carrier.is_carrying(), "package handed over")
	_check(wallet.gold == gold_before + definition.reward.gold, "wallet paid %d gold (now %d)" % [definition.reward.gold, wallet.gold])
	_check(dialogue.is_open() and dialogue.name_label.text == npc.npc_name, "%s's thanks shown in the dialogue box" % npc.npc_name)
	_press(&"ui_cancel")
	await _frames(2)


# --- tests -------------------------------------------------------------------

func _test_services() -> void:
	print("[Gameplay services]")
	_check(get_nodes_in_group(QuestManager.GROUP).size() == 1, "exactly one QuestManager in the village")
	_check(manager != null and manager.get_quest_ids().size() == 3, "quest data loaded (%d quests)" % (manager.get_quest_ids().size() if manager else 0))
	_check(wallet != null and wallet.gold == 0, "courier wallet present and empty")
	_check(level.get_child(0).name == &"GameplayServices", "services are the first child, ready before pickups query them")


func _test_placement() -> void:
	print("[Placement]")
	var spot := level.get_node("PostOffice/Markers/QuestBoardSpot") as Node3D
	_check(board.is_in_group(QuestBoard.GROUP) and board.global_position.is_equal_approx(spot.global_position), "quest board stands on QuestBoardSpot")
	# Phase 7: the guild board stands on the plaza just outside the post-office gate.
	var gate := Vector2(-8.0, -6.0)
	_check(not _inside_post_office(board.global_position) and Vector2(board.global_position.x, board.global_position.z).distance_to(gate) < 6.0, "quest board stands on the plaza by the post-office gate")
	for package_id in [&"pkg_ordinary_parcel", &"pkg_dragon_egg", &"pkg_potion_crate"]:
		var pickup := _pickup_for(package_id)
		_check(pickup != null and _inside_post_office(pickup.global_position), "%s pickup placed in the post office" % package_id)
		_check(pickup != null and not pickup.visible and not pickup.is_available(), "%s pickup hidden until a quest needs it" % package_id)
	var clearing := level.get_node("ForestEntrance/Markers/ForestClearingSpot/ForestClearing") as DestinationArea
	_check(clearing != null and clearing.destination_id == &"forest_clearing", "forest_clearing destination at ForestClearingSpot")
	var mage := _npc("MageElowen")
	_check(clearing != null and Vector2(mage.global_position.x - clearing.global_position.x, mage.global_position.z - clearing.global_position.z).length() < 4.0,
			"Mage Elowen waits inside the clearing ring")
	for node_name in QUEST_NPCS:
		_check(_npc(node_name).get_node_or_null("QuestBehaviour") is QuestNPCBehaviour, "%s has a QuestBehaviour" % node_name)
	_check(_npc("VillagerPip").get_node_or_null("QuestBehaviour") == null, "Villager Pip is not a quest NPC")


func _inside_post_office(world_position: Vector3) -> bool:
	var local := (level.get_node("PostOffice") as Node3D).to_local(world_position)
	return absf(local.x) < 6.0 and absf(local.z) < 5.0


func _test_quest_data_resolves() -> void:
	print("[Quest data resolves in the village]")
	var npc_ids := {}
	for npc in level.get_node("NPCs").get_children():
		npc_ids[(npc as NPC).npc_id] = true
	var destinations := {}
	for area in level.find_children("*", "DestinationArea", true, false):
		destinations[(area as DestinationArea).destination_id] = true
	for quest_id in manager.get_quest_ids():
		var definition := manager.get_definition(quest_id)
		_check(npc_ids.has(definition.giver_id), "%s giver '%s' is in the village" % [quest_id, definition.giver_id])
		_check(_pickup_for(definition.package.package_id) != null, "%s package '%s' has a pickup" % [quest_id, definition.package.package_id])
		for objective in definition.objectives:
			match objective.type:
				QuestObjective.Type.TALK_TO_NPC, QuestObjective.Type.DELIVER_PACKAGE:
					_check(npc_ids.has(objective.target_id), "%s NPC target '%s' is in the village" % [quest_id, objective.target_id])
				QuestObjective.Type.REACH_DESTINATION:
					_check(destinations.has(objective.target_id), "%s destination '%s' is in the village" % [quest_id, objective.target_id])


func _test_hud_layout() -> void:
	print("[HUD layout]")
	_check(hud.player == player, "gameplay HUD bound to the player")
	_check(hud.layer < journal.layer, "gameplay HUD draws under the journal (%d < %d)" % [hud.layer, journal.layer])
	_check(not hud.package_indicator.get_global_rect().intersects(journal.hint_label.get_global_rect()),
			"journal hint does not overlap the package indicator")
	var toast_top := hud.quest_notification.get_global_rect().position.y
	_check(toast_top >= banner.banner.get_global_rect().end.y, "toasts sit below the location banner (%.0f >= %.0f)" % [toast_top, banner.banner.get_global_rect().end.y])


func _test_board_window_is_modal() -> void:
	print("[Quest board window]")
	var opened := [0]
	board_ui.opened.connect(func() -> void: opened[0] += 1)
	await _stand_near(board, board.global_position + Vector3(0, 0, 2))
	_check(player.interaction.focused == board.interactable, "player focuses the board from the hall")
	_check(prompt.panel.visible and prompt.label.text == "[E] Read Courier Guild Board", "prompt reads '%s'" % prompt.label.text)

	_press(&"interact")
	await _frames(2)
	_check(board_ui.is_open() and opened[0] == 1, "E opens the board window and emits opened")
	_check(board_ui.is_in_group(QuestJournal.MODAL_GROUP), "open board window is modal")
	_check(not prompt.panel.visible, "interaction prompt hidden under the board window")
	_check(not player.input_enabled, "player input paused")
	_check(board_ui.accept_buttons.size() == 3, "board lists the three contracts")

	_press(&"toggle_journal")
	await _frames(2)
	_check(not journal.is_open(), "journal does not open over the board window")
	dialogue.show_line("Tester", "Hello.")
	dialogue.skip_typing()
	_check(board_ui.accept_buttons[Q1].has_focus(), "first Accept button has keyboard focus")
	_press(&"ui_accept")
	await _frames(2)
	_check(dialogue.is_open(), "dialogue ignores input while the board is open")
	_check(manager.get_status(Q1) == S.ACCEPTED, "ui_accept goes to the focused Accept button (Q1 %s)" % _status(Q1))
	dialogue.close()

	_press(&"ui_cancel")
	await _frames(2)
	_check(not board_ui.is_open() and not board_ui.is_in_group(QuestJournal.MODAL_GROUP), "Escape closes the board window")
	_check(prompt.panel.visible and player.input_enabled, "prompt and input come back")


func _test_q1_first_delivery() -> void:
	print("[Q1: board -> postmaster -> parcel -> merchant]")
	# Q1 was accepted with the keyboard in _test_board_window_is_modal.
	_check(manager.get_status(Q1) == S.ACCEPTED, "Q1 starts accepted")
	_check(not _pickup_for(&"pkg_ordinary_parcel").visible, "parcel still hidden before talking to the postmaster")

	var bram := _npc("PostmasterBram")
	await _interact_with(bram, bram.interactable, Vector3(-15, 0, -5), "Postmaster Bram across the counter", 1.5)
	_check(manager.get_status(Q1) == S.ACTIVE, "talking to Bram activates Q1 (%s)" % _status(Q1))
	_check(dialogue.is_open() and dialogue.name_label.text == "Postmaster Bram", "Bram's quest line shows in the dialogue box")
	_press(&"ui_cancel")
	await _frames(2)

	_press(&"toggle_journal")
	await _frames(2)
	var titles := journal.get_visible_entries().map(func(e: Dictionary) -> String: return e["title"])
	_check(journal.is_open() and titles == [manager.get_definition(Q1).title], "journal lists Q1 in progress (%s)" % [titles])
	_check(not journal.source_label.visible, "journal reads the live quest manager")
	_press(&"toggle_journal")
	await _frames(2)

	await _pick_up(&"pkg_ordinary_parcel")
	_check(hud.package_indicator.visible, "package indicator shows the carried parcel")
	var mira := _npc("MerchantMira")
	await _deliver_to(mira, (level.get_node("Markers/MarketDeliverySpot") as Node3D).global_position, Q1)


func _test_q2_dragon_egg() -> void:
	print("[Q2: dragon egg to the Moonstone Clearing]")
	await _accept_on_board(Q2)
	await _pick_up(&"pkg_dragon_egg")
	var clearing := level.get_node("ForestEntrance/Markers/ForestClearingSpot/ForestClearing") as DestinationArea
	player.teleport_to(clearing.global_position)
	rig.snap_to_target()
	await _frames(6)
	_check(manager.get_current_objective(Q2) != null and manager.get_current_objective(Q2).type == QuestObjective.Type.DELIVER_PACKAGE,
			"entering the clearing completes the destination objective")
	var mage := _npc("MageElowen")
	await _deliver_to(mage, clearing.global_position, Q2)


func _test_q3_potion_crate() -> void:
	print("[Q3: potion crate to the alchemist]")
	await _accept_on_board(Q3)
	await _pick_up(&"pkg_potion_crate")
	var corvin := _npc("AlchemistCorvin")
	await _deliver_to(corvin, (level.get_node("Markers/AlchemyDeliverySpot") as Node3D).global_position, Q3)
	_check(wallet.gold == 260, "all three contracts paid out (%d gold)" % wallet.gold)
	journal.open()
	_check(journal.tab_archive.text == "Archive (3)", "journal archives all three deliveries (%s)" % journal.tab_archive.text)
	journal.close()
