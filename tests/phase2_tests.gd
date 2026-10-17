extends SceneTree
## Phase 2 automated checks (quests, packages, delivery, rewards, UI wiring).
##   godot --headless --path . --script res://tests/phase2_tests.gd
## Exit code = number of failed checks. Run tests/phase1_tests.gd for Phase 1 regression.

const SANDBOX := "res://scenes/gameplay/sandbox/phase2_delivery_sandbox.tscn"
const Q1 := &"q001_first_delivery"
const Q2 := &"q002_dragon_egg"
const Q3 := &"q003_unstable_potion"
const S := QuestState.Status

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var manager: QuestManager
var wallet: CourierWallet
var player: PlayerController
var carrier: PackageCarrier
var board: QuestBoard
var board_ui: QuestBoardUI
var hud: GameplayHUD
var npcs: Dictionary = {}
var pickups: Dictionary = {}
var transitions: Dictionary = {}  # quest_id -> Array of status names
var rejections: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	level = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	manager = QuestManager.find(self)
	wallet = CourierWallet.find(self)
	player = level.get_node("Player")
	carrier = PackageCarrier.find_on(player)
	board = level.get_node("PostOffice/QuestBoard")
	board_ui = level.get_node("QuestBoardUI")
	hud = level.get_node("GameplayHUD")
	for key in ["Postmaster", "Merchant", "Alchemist", "Mage"]:
		npcs[key] = level.get_node("NPCs/" + key)
	for key in ["ParcelPickup", "DragonEggPickup", "PotionCratePickup"]:
		pickups[key] = level.get_node("PostOffice/Pickups/" + key)
	manager.quest_state_changed.connect(func(id: StringName, new_status: QuestState.Status, _old):
		if not transitions.has(id):
			transitions[id] = []
		transitions[id].append(QuestState.status_name(new_status)))
	manager.delivery_rejected.connect(func(id, npc_id, result): rejections.append([id, npc_id, result]))
	await _frames(10)

	_test_data_loaded()
	_test_npc_ids()
	_test_dialogue_before_quests()
	await _test_board_ui_accept_q1()
	_test_duplicate_and_incompatible_accept()
	await _test_pickup_gating_and_talk()
	await _test_pickup()
	await _test_hands_full_and_drop()
	_test_wrong_recipient()
	_test_correct_delivery_q1()
	_test_duplicate_reward_prevention()
	await _test_q2_with_destination()
	await _test_q3_fail_and_retry()
	_test_invalid_transitions()
	await _test_e_key_delivery_end_to_end()

	print("\n=== Phase 2 tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


# --- helpers -------------------------------------------------------------------

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


func _talk(npc_key: String) -> String:
	var npc: NPC = npcs[npc_key]
	npc.interactable.interact(player)
	return npc.speech_label.text


func _press(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _status(id: StringName) -> String:
	return QuestState.status_name(manager.get_status(id))


func _toasts_contain(text: String) -> bool:
	for message in hud.quest_notification.history:
		if message.contains(text):
			return true
	return false


# --- tests ---------------------------------------------------------------------

func _test_data_loaded() -> void:
	print("[Data]")
	_check(manager.get_quest_ids().size() == 3, "3 quests registered")
	var expected := {
		Q1: [50, 5, &"village_merchant", &"pkg_ordinary_parcel"],
		Q2: [120, 20, &"forest_mage", &"pkg_dragon_egg"],
		Q3: [90, 15, &"village_alchemist", &"pkg_potion_crate"],
	}
	for id in expected:
		var d := manager.get_definition(id)
		var e: Array = expected[id]
		_check(d != null and d.reward.gold == e[0] and d.reward.reputation == e[1], "%s reward %d Gold / %d Rep" % [id, e[0], e[1]])
		_check(d.package.recipient_id == e[2] and d.package.package_id == e[3] and d.package.quest_id == id, "%s package %s -> %s" % [id, e[3], e[2]])
		var last := d.objectives[-1]
		_check(last.type == QuestObjective.Type.DELIVER_PACKAGE and last.target_id == e[2], "%s ends with DELIVER to recipient" % id)
		_check(manager.get_status(id) == S.AVAILABLE, "%s starts AVAILABLE" % id)
	var types := {}
	for id in expected:
		for o in manager.get_definition(id).objectives:
			types[o.type] = true
	_check(types.size() == 4, "all 4 objective types used by the data")
	_check(manager.get_available_quests().size() == 3, "multiple quests available at once")


func _test_npc_ids() -> void:
	print("[NPC identifiers]")
	var ids := {}
	for key in npcs:
		ids[npcs[key].npc_id] = true
	_check(ids.size() == 4 and not ids.has(&""), "4 NPCs with unique non-empty ids %s" % [ids.keys()])


func _test_dialogue_before_quests() -> void:
	print("[Dialogue: no quest]")
	var merchant: NPC = npcs["Merchant"]
	_check(_talk("Merchant") == merchant.lines[0], "merchant uses default line before any quest")
	var postmaster: NPC = npcs["Postmaster"]
	_check(_talk("Postmaster") == postmaster.lines[0], "postmaster talk does nothing before Q1 is accepted")
	_check(manager.get_status(Q1) == S.AVAILABLE, "talking early does not advance Q1")


func _test_board_ui_accept_q1() -> void:
	print("[Quest board UI]")
	player.teleport_to(Vector3(0, 0, -2))
	await _frames(6)
	_check(player.interaction.focused == board.interactable, "board focused when standing in front of it")
	_press(&"interact")
	await _frames(2)
	_check(board_ui.is_open(), "E opens quest board UI")
	_check(not player.input_enabled, "player input frozen while board open")
	_check(board_ui.accept_buttons.size() == 3, "board lists 3 contracts")
	var all_enabled := true
	for id in board_ui.accept_buttons:
		all_enabled = all_enabled and not board_ui.accept_buttons[id].disabled
	_check(all_enabled, "all contracts acceptable initially")
	var entry_text := _collect_label_text(board_ui.entry_list)
	_check(entry_text.contains("Merchant Mira") and entry_text.contains("Village Market") and entry_text.contains("50 Gold, 5 Reputation"), "entry shows destination and reward")
	board_ui.accept_buttons[Q1].pressed.emit()
	await _frames(1)
	_check(manager.get_status(Q1) == S.ACCEPTED, "Accept button accepts Q1 (status %s)" % _status(Q1))
	_check(manager.get_active_delivery_id() == Q1, "Q1 occupies the delivery slot")
	_check(board_ui.accept_buttons[Q2].disabled and board_ui.accept_buttons[Q3].disabled, "other contracts disabled while a delivery is active")
	_check(not board_ui.accept_buttons[Q1].visible, "accepted contract no longer shows Accept")
	_check(_toasts_contain("Contract accepted: First Delivery"), "acceptance notification shown")
	_press(&"ui_cancel")
	await _frames(2)
	_check(not board_ui.is_open(), "Esc closes the board")
	_check(player.input_enabled, "player input restored after closing")
	_check(hud.quest_tracker.visible and hud.quest_tracker.title_label.text == "First Delivery", "tracker shows active quest")


func _collect_label_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for child in node.get_children():
		text += _collect_label_text(child)
	return text


func _test_duplicate_and_incompatible_accept() -> void:
	print("[Acceptance rules]")
	_check(manager.accept_quest(Q1) == QuestManager.AcceptResult.ALREADY_ACCEPTED, "duplicate accept rejected")
	_check(manager.accept_quest(Q2) == QuestManager.AcceptResult.DELIVERY_IN_PROGRESS, "second delivery rejected")
	_check(manager.accept_quest(&"nope") == QuestManager.AcceptResult.UNKNOWN_QUEST, "unknown quest rejected")
	_check(manager.get_status(Q2) == S.AVAILABLE, "rejected quest stays AVAILABLE")
	_check(transitions.get(Q1, []).count("ACCEPTED") == 1, "only one ACCEPTED transition emitted")


func _test_pickup_gating_and_talk() -> void:
	print("[Talk objective + pickup gating]")
	var parcel: PackagePickup = pickups["ParcelPickup"]
	_check(not parcel.is_available() and not parcel.visible, "parcel hidden until postmaster briefing")
	var line := _talk("Postmaster")
	_check(line.contains("first parcel"), "postmaster gives briefing line")
	_check(manager.get_status(Q1) == S.ACTIVE, "talk progress activates quest (ACCEPTED -> ACTIVE)")
	await _frames(1)
	_check(parcel.is_available() and parcel.visible, "parcel appears after briefing")
	_check(not pickups["DragonEggPickup"].is_available() and not pickups["PotionCratePickup"].is_available(), "other packages stay hidden")
	var index_before := manager.get_state(Q1).objective_index
	var repeat := _talk("Postmaster")
	_check(manager.get_state(Q1).objective_index == index_before and not repeat.contains("first parcel"), "repeat talk does not re-complete objective")


func _test_pickup() -> void:
	print("[Package pickup]")
	var parcel: PackagePickup = pickups["ParcelPickup"]
	parcel.interactable.interact(player)
	await _frames(1)
	_check(carrier.is_carrying() and carrier.get_package().get_package_id() == &"pkg_ordinary_parcel", "player carries the parcel")
	_check(carrier.get_child_count() == 1, "package visual attached to carrier")
	_check(not parcel.is_available(), "source pickup hidden after pickup")
	_check(manager.get_current_objective(Q1).type == QuestObjective.Type.DELIVER_PACKAGE, "objective advanced to delivery")
	_check(hud.package_indicator.visible and hud.package_indicator.name_label.text == "Carrying: Ordinary Parcel", "package indicator shows parcel")
	_check(hud.package_indicator.integrity_label.text == "Integrity: 100%", "indicator shows integrity")


func _test_hands_full_and_drop() -> void:
	print("[Hands full / drop / re-pickup]")
	var blocked := [false]
	var on_blocked := func(_p, _r): blocked[0] = true
	carrier.pickup_blocked.connect(on_blocked)
	var extra := PackageInstance.new(load("res://data/packages/pkg_dragon_egg.tres"))
	_check(not carrier.pick_up(extra), "cannot carry two packages")
	_check(blocked[0] and carrier.get_package().get_package_id() == &"pkg_ordinary_parcel", "pickup_blocked emitted, parcel kept")
	carrier.pickup_blocked.disconnect(on_blocked)

	var original := carrier.get_package()
	original.set_integrity(80.0)
	_check(hud.package_indicator.integrity_label.text == "Integrity: 80%", "indicator updates on integrity change")
	var dropped := carrier.drop_package()
	await _frames(1)
	_check(not carrier.is_carrying() and dropped != null and dropped.is_inside_tree(), "drop spawns a world pickup")
	_check(dropped.is_dropped() and dropped.is_available(), "dropped pickup is available")
	_check(not hud.package_indicator.visible, "indicator hidden after drop")
	_check(manager.get_status(Q1) == S.ACTIVE, "dropping does not change quest state")
	dropped.interactable.interact(player)
	await _frames(1)
	_check(carrier.get_package() == original and is_equal_approx(carrier.get_package().integrity, 80.0), "re-pickup returns same package with integrity kept")
	_check(not is_instance_valid(dropped) or dropped.is_queued_for_deletion(), "dropped pickup removed after re-pickup")
	original.set_integrity(100.0)


func _test_wrong_recipient() -> void:
	print("[Wrong recipient]")
	var gold := wallet.gold
	rejections.clear()
	var line := _talk("Alchemist")
	_check(carrier.is_carrying(), "alchemist does not take the parcel")
	_check(line.contains("Merchant Mira"), "alchemist redirects to the correct recipient: '%s'" % line)
	_check(rejections.size() == 1 and rejections[0][2] == QuestManager.DeliveryResult.WRONG_RECIPIENT, "delivery_rejected(WRONG_RECIPIENT) emitted")
	_talk("Mage")
	_check(carrier.is_carrying() and manager.get_status(Q1) == S.ACTIVE, "mage also rejects; quest still ACTIVE")
	_check(wallet.gold == gold, "no reward on wrong delivery")
	_check(_toasts_contain("Wrong recipient"), "rejection notification shown")


func _test_correct_delivery_q1() -> void:
	print("[Correct delivery]")
	var line := _talk("Merchant")
	_check(not carrier.is_carrying(), "merchant takes the parcel; package removed")
	_check(line == manager.get_definition(Q1).objectives[-1].completion_line, "merchant says delivery line")
	_check(manager.get_status(Q1) == S.REWARDED, "Q1 REWARDED (got %s)" % _status(Q1))
	_check(wallet.gold == 50 and wallet.reputation == 5, "wallet 50 Gold / 5 Rep (got %d / %d)" % [wallet.gold, wallet.reputation])
	_check(transitions[Q1] == ["ACCEPTED", "ACTIVE", "COMPLETED", "REWARDED"], "Q1 transitions %s" % [transitions[Q1]])
	_check(manager.get_active_delivery_id() == &"", "delivery slot released")
	_check(hud.wallet_display.gold_label.text == "Gold: 50" and hud.wallet_display.reputation_label.text == "Reputation: 5", "wallet display updated")
	_check(_toasts_contain("Delivery complete: First Delivery"), "completion notification shown")
	_check(not hud.quest_tracker.visible, "tracker hidden with no active delivery")


func _test_duplicate_reward_prevention() -> void:
	print("[Duplicate reward prevention]")
	_check(not manager.grant_reward(Q1), "grant_reward on rewarded quest returns false")
	var fake := PackageInstance.new(load("res://data/packages/pkg_ordinary_parcel.tres"))
	_check(manager.try_deliver(&"village_merchant", fake) == QuestManager.DeliveryResult.QUEST_NOT_ACTIVE, "second delivery of Q1 parcel rejected")
	_check(manager.accept_quest(Q1) == QuestManager.AcceptResult.NOT_AVAILABLE, "rewarded quest cannot be re-accepted")
	var after := _talk("Merchant")
	_check(after == manager.get_definition(Q1).recipient_after_line, "merchant dialogue changes after delivery")
	_check(wallet.gold == 50 and wallet.reputation == 5, "wallet unchanged after repeat attempts")
	_check(transitions[Q1].count("REWARDED") == 1, "REWARDED emitted once")


func _test_q2_with_destination() -> void:
	print("[Q2: reach destination + deliver]")
	_check(manager.accept_quest(Q2) == QuestManager.AcceptResult.OK, "Q2 accepted after Q1 finished")
	await _frames(1)
	_check(_talk("Mage") == manager.get_definition(Q2).recipient_waiting_line, "mage waiting line while Q2 in progress")
	var egg: PackagePickup = pickups["DragonEggPickup"]
	_check(egg.is_available(), "egg pickup visible")
	egg.interactable.interact(player)
	await _frames(1)
	_check(carrier.get_package().get_package_id() == &"pkg_dragon_egg", "carrying dragon egg")
	_check(manager.try_deliver(&"forest_mage", carrier.get_package()) == QuestManager.DeliveryResult.NOT_READY, "delivery NOT_READY before reaching the clearing")
	_check(carrier.is_carrying(), "egg kept after NOT_READY")
	player.teleport_to(Vector3(-14, 0, 12))
	await _frames(4)
	_check(manager.get_current_objective(Q2).type == QuestObjective.Type.DELIVER_PACKAGE, "entering Forest Clearing completes REACH_DESTINATION")
	_talk("Mage")
	_check(manager.get_status(Q2) == S.REWARDED and wallet.gold == 170 and wallet.reputation == 25, "Q2 rewarded: 170 Gold / 25 Rep total (got %d / %d)" % [wallet.gold, wallet.reputation])


func _test_q3_fail_and_retry() -> void:
	print("[Q3: failure, retry, completion]")
	manager.accept_quest(Q3)
	await _frames(1)
	_check(_talk("Alchemist") == manager.get_definition(Q3).recipient_waiting_line, "alchemist waiting line while Q3 in progress")
	pickups["PotionCratePickup"].interactable.interact(player)
	await _frames(1)
	var dropped := carrier.drop_package()
	await _frames(1)
	dropped.interactable.interact(player)
	await _frames(1)
	_check(carrier.is_carrying(), "carrying potion crate")
	_check(manager.fail_quest(Q3, "test"), "fail_quest succeeds on active quest")
	await _frames(1)
	_check(manager.get_status(Q3) == S.FAILED and not carrier.is_carrying(), "FAILED and package confiscated")
	_check(manager.get_active_delivery_id() == &"", "failed quest frees delivery slot")
	_check(_toasts_contain("Delivery failed: Unstable Potion"), "failure notification shown")
	var gold := wallet.gold
	_check(not manager.grant_reward(Q3), "no reward for failed quest")
	_check(manager.reset_failed_quest(Q3) and manager.get_status(Q3) == S.AVAILABLE, "failed quest can be reset to AVAILABLE")
	manager.accept_quest(Q3)
	await _frames(1)
	_check(pickups["PotionCratePickup"].is_available(), "crate pickup available again on retry")
	pickups["PotionCratePickup"].interactable.interact(player)
	_talk("Alchemist")
	_check(manager.get_status(Q3) == S.REWARDED and wallet.gold == gold + 90, "Q3 rewarded once on retry (gold %d)" % wallet.gold)
	_check(transitions[Q3] == ["ACCEPTED", "ACTIVE", "FAILED", "AVAILABLE", "ACCEPTED", "ACTIVE", "COMPLETED", "REWARDED"], "Q3 transitions %s" % [transitions[Q3]])


func _test_invalid_transitions() -> void:
	print("[Invalid transitions]")
	_check(not manager.fail_quest(Q1), "cannot fail a rewarded quest")
	_check(not manager.reset_failed_quest(Q2), "cannot reset a non-failed quest")
	_check(manager.get_status(Q1) == S.REWARDED and manager.get_status(Q2) == S.REWARDED, "states unchanged")
	_check(wallet.gold == 260 and wallet.reputation == 40, "final wallet 260 Gold / 40 Rep (got %d / %d)" % [wallet.gold, wallet.reputation])


func _test_e_key_delivery_end_to_end() -> void:
	print("[E-key end-to-end via InteractionDetector]")
	# Fresh manager state isn't needed: verify the E path reaches NPC dialogue with quest behaviour.
	var merchant: NPC = npcs["Merchant"]
	player.teleport_to(merchant.global_position + Vector3(-1.5, 0, 0))
	await _frames(6)
	_check(player.interaction.focused == merchant.interactable, "merchant focused")
	var count := merchant.interaction_count
	_press(&"interact")
	await _frames(2)
	_check(merchant.interaction_count == count + 1 and merchant.speech_label.text == manager.get_definition(Q1).recipient_after_line, "E press routes through NPC quest behaviour")
