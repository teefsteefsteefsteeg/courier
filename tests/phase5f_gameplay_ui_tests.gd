extends SceneTree
## Phase 5F gameplay / UI checks in the real village: NPC quest markers, context
## interaction prompts, delivery feedback (toast kinds, NPC thanks), the quest tracker
## stage/step/reward lines, the courier rank and the wallet payout delta.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5f_gameplay_ui_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const S := QuestState.Status
const M := QuestNPCBehaviour.Marker
const Q1 := &"q001_first_delivery"
const Q2 := &"q002_dragon_egg"
const Q3 := &"q003_unstable_potion"
const QUEST_NPCS := ["PostmasterBram", "MerchantMira", "AlchemistCorvin", "MageElowen"]

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var manager: QuestManager
var wallet: CourierWallet
var carrier: PackageCarrier
var hud: GameplayHUD
var prompt: InteractionPrompt
var dialogue: DialogueBox
var board: QuestBoard
var board_ui: QuestBoardUI


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_rank_math()
	_test_rank_signal()
	_test_marker_without_manager()

	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	manager = QuestManager.find(self)
	wallet = CourierWallet.find(self)
	carrier = PackageCarrier.find_on(player)
	hud = level.get_node("GameplayHUD")
	prompt = level.get_node("InteractionPrompt")
	dialogue = level.get_node("DialogueBox")
	board = level.get_node("PostOffice/Markers/QuestBoardSpot/QuestBoard")
	board_ui = level.get_node("QuestBoardUI")
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	await _frames(20)

	_test_markers_attached()
	await _test_default_prompts()
	await _test_q1_feedback()
	await _test_q2_not_ready_and_rank_up()
	await _test_board_feedback()
	_test_hud_fits()

	print("\n=== Phase 5F gameplay/UI tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _npc(node_name: String) -> NPC:
	return level.get_node("NPCs/" + node_name) as NPC


func _behaviour(node_name: String) -> QuestNPCBehaviour:
	return _npc(node_name).get_node_or_null("QuestBehaviour") as QuestNPCBehaviour


func _marker(node_name: String) -> int:
	var behaviour := _behaviour(node_name)
	behaviour.refresh_marker()
	return behaviour.marker


func _marker_name(node_name: String) -> String:
	return QuestNPCBehaviour.marker_name(_marker(node_name))


func _pickup_for(package_id: StringName) -> PackagePickup:
	for node in level.get_node("PostOffice/Markers/ParcelPickupSpot").get_children():
		var pickup := node as PackagePickup
		if pickup != null and pickup.package_definition.package_id == package_id:
			return pickup
	return null


## Puts the player `distance` metres from `target`, on the side facing `toward`.
func _stand_near(target: Node3D, toward: Vector3, distance: float = 1.2) -> void:
	var offset := toward - target.global_position
	offset.y = 0.0
	player.teleport_to(target.global_position + offset.normalized() * distance)
	rig.snap_to_target()
	await _frames(6)


func _spot(path: String) -> Vector3:
	return (level.get_node(path) as Node3D).global_position


func _toast_index(text: String) -> int:
	var history := hud.quest_notification.history
	for i in range(history.size() - 1, -1, -1):
		if history[i].contains(text):
			return i
	return -1


func _close_dialogue() -> void:
	dialogue.close()
	await _frames(1)


# --- pure logic --------------------------------------------------------------

func _test_rank_math() -> void:
	print("[Courier rank thresholds]")
	_check(CourierWallet.rank_for(0) == 0 and CourierWallet.rank_for(-10) == 0, "0 and negative reputation are Novice")
	_check(CourierWallet.rank_for(14) == 0 and CourierWallet.rank_for(15) == 1, "15 reputation reaches Apprentice")
	_check(CourierWallet.rank_for(40) == 2 and CourierWallet.rank_for(75) == 3, "40 is Journeyman, 75 is Trusted")
	_check(CourierWallet.rank_for(100000) == CourierWallet.RANKS.size() - 1, "huge reputation caps at the top rank")
	_check(is_equal_approx(CourierWallet.rank_progress(25), 0.5), "progress is relative to the rank band (%.2f)" % CourierWallet.rank_progress(25))
	_check(is_equal_approx(CourierWallet.rank_progress(1000), 1.0) and is_equal_approx(CourierWallet.rank_progress(-5), 0.0), "progress is clamped")
	_check(CourierWallet.rank_title(1) == "Apprentice Courier" and CourierWallet.rank_title(99) == "Renowned Courier", "rank titles (out of range clamps)")


func _test_rank_signal() -> void:
	print("[Courier rank signal]")
	var purse := CourierWallet.new()
	var ranks: Array = []
	purse.rank_changed.connect(func(new_rank: int, old_rank: int): ranks.append([new_rank, old_rank]))
	purse.add_reputation(10)
	_check(ranks.is_empty() and purse.get_reputation_to_next_rank() == 5, "no rank change below the threshold (5 to next)")
	purse.add_reputation(10)
	_check(ranks == [[1, 0]] and purse.get_rank_title() == "Apprentice Courier", "crossing 15 emits rank_changed(1, 0) once (%s)" % [ranks])
	purse.add_reputation(-20)
	_check(ranks.size() == 2 and ranks[1] == [0, 1], "losing reputation emits a rank drop")
	purse.free()


func _test_marker_without_manager() -> void:
	print("[Markers without quest services]")
	_check(QuestNPCBehaviour.marker_for(null, &"postmaster", null) == M.NONE, "no QuestManager -> no marker")
	var interactable := Interactable.new()
	interactable.prompt_verb = "Open"
	interactable.display_name = "Crate"
	_check(interactable.get_prompt_text_for(null) == "Open Crate", "context prompt falls back to the default prompt")
	interactable.free()


# --- village -----------------------------------------------------------------

func _test_markers_attached() -> void:
	print("[Quest markers]")
	for node_name in QUEST_NPCS:
		var label := _npc(node_name).get_node_or_null(String(QuestNPCBehaviour.MARKER_NAME)) as Label3D
		_check(label != null and label == _behaviour(node_name).marker_label, "%s has a quest marker label" % node_name)
		_check(_marker(node_name) == M.NONE and label != null and not label.visible, "%s marker hidden before any contract" % node_name)
		_check(label != null and label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and label.position.y > 2.5, "%s marker floats above the head" % node_name)
	_check(_npc("VillagerPip").get_node_or_null(String(QuestNPCBehaviour.MARKER_NAME)) == null, "Villager Pip has no quest marker")


func _test_default_prompts() -> void:
	print("[Default prompts are unchanged]")
	await _stand_near(_npc("PostmasterBram"), Vector3(-15, 0, -5), 1.5)
	_check(prompt.label.text == "[E] Talk to Postmaster Bram" and not prompt.is_context_prompt(), "Bram prompt with empty hands: '%s'" % prompt.label.text)
	await _stand_near(board, board.global_position + Vector3(0, 0, 2))
	_check(prompt.label.text == "[E] Read Courier Guild Board", "board prompt unchanged: '%s'" % prompt.label.text)


func _test_q1_feedback() -> void:
	print("[Q1: markers, tracker, context prompt, delivery feedback]")
	var bram := _npc("PostmasterBram")
	var mira := _npc("MerchantMira")
	var corvin := _npc("AlchemistCorvin")
	var tracker := hud.quest_tracker
	_check(manager.accept_quest(Q1) == QuestManager.AcceptResult.OK, "Q1 accepted")
	await _frames(2)
	_check(_marker("PostmasterBram") == M.TALK and _behaviour("PostmasterBram").marker_label.text == "!", "Bram shows '!' while Q1 wants a briefing")
	_check(_behaviour("PostmasterBram").marker_label.visible, "Bram's marker is visible")
	_check(_marker("MerchantMira") == M.AWAITING, "Mira shows a dim '?' while her parcel is on its way (%s)" % _marker_name("MerchantMira"))
	_check(_marker("AlchemistCorvin") == M.NONE, "Corvin has no marker for Q1")
	_check(tracker.visible and tracker.title_label.text == "First Delivery", "tracker shows Q1")
	_check(tracker.header_label.text == "CONTRACT ACCEPTED · STEP 1/3", "tracker header '%s'" % tracker.header_label.text)
	_check(tracker.reward_label.visible and tracker.reward_label.text == "Reward: 50 Gold, 5 Reputation", "tracker reward '%s'" % tracker.reward_label.text)

	var changes := tracker.objective_changes
	bram.interactable.interact(player)
	await _frames(2)
	_check(manager.get_status(Q1) == S.ACTIVE, "briefing activates Q1")
	_check(_marker("PostmasterBram") == M.NONE, "Bram's '!' clears after the briefing")
	_check(tracker.header_label.text == "ACTIVE DELIVERY · STEP 2/3", "tracker header '%s'" % tracker.header_label.text)
	_check(tracker.objective_changes == changes + 1 and tracker.is_highlighting(), "new objective flashes in the tracker")
	await _close_dialogue()

	var parcel := _pickup_for(&"pkg_ordinary_parcel")
	parcel.interactable.interact(player)
	await _frames(2)
	_check(carrier.is_carrying(), "parcel picked up")
	_check(_marker("MerchantMira") == M.DELIVER and _behaviour("MerchantMira").marker_label.text == "?", "Mira shows a bright '?' once the parcel is in hand")
	_check(_behaviour("MerchantMira").marker_label.modulate.a > 0.9, "deliverable marker is fully opaque")
	_check(tracker.header_label.text == "READY TO DELIVER · STEP 3/3", "tracker header '%s'" % tracker.header_label.text)

	print("[Wrong recipient feedback]")
	await _stand_near(corvin, _spot("Markers/AlchemyDeliverySpot"))
	_check(player.interaction.focused == corvin.interactable, "player focuses Corvin")
	_check(prompt.label.text == "[E] Talk to Alchemist Corvin" and not prompt.is_context_prompt(), "wrong recipient keeps the talk prompt: '%s'" % prompt.label.text)
	corvin.interactable.interact(player)
	await _frames(1)
	var wrong := _toast_index("Check the address: Merchant Mira, Village Market")
	_check(wrong >= 0 and hud.quest_notification.kind_history[wrong] == QuestNotification.KIND_WARNING, "wrong-recipient toast names the right address, as a warning")
	_check(carrier.is_carrying(), "Corvin does not take the parcel")
	await _close_dialogue()

	print("[Dropped package stage]")
	var dropped := carrier.drop_package()
	await _frames(2)
	_check(tracker.header_label.text == "PACKAGE DROPPED · STEP 3/3", "tracker header '%s'" % tracker.header_label.text)
	_check(_marker("MerchantMira") == M.AWAITING, "Mira's '?' dims while the parcel is on the ground")
	var drop_toast := _toast_index("Dropped: Ordinary Parcel")
	_check(drop_toast >= 0 and hud.quest_notification.kind_history[drop_toast] == QuestNotification.KIND_WARNING, "drop toast is a warning")
	dropped.interactable.interact(player)
	await _frames(2)
	_check(carrier.is_carrying() and tracker.header_label.text == "READY TO DELIVER · STEP 3/3", "re-pickup restores READY TO DELIVER")

	print("[Context prompt + handover]")
	await _stand_near(mira, _spot("Markers/MarketDeliverySpot"))
	_check(player.interaction.focused == mira.interactable, "player focuses Mira")
	_check(prompt.label.text == "[E] Deliver Ordinary Parcel to Merchant Mira", "context prompt '%s'" % prompt.label.text)
	_check(prompt.is_context_prompt() and prompt.label.get_theme_color(&"font_color") == InteractionPrompt.CONTEXT_COLOR, "context prompt is highlighted")
	var gold_before := wallet.gold
	mira.interactable.interact(player)
	await _frames(2)
	_check(manager.get_status(Q1) == S.REWARDED and wallet.gold == gold_before + 50, "Q1 delivered and paid")
	_check(_behaviour("MerchantMira").marker == M.THANKS and _behaviour("MerchantMira").marker_label.text == "✓", "Mira shows a thank-you tick")
	var done := _toast_index("Delivery complete: First Delivery")
	_check(done >= 0 and hud.quest_notification.kind_history[done] == QuestNotification.KIND_SUCCESS, "completion toast is a success toast")
	var display := hud.wallet_display
	_check(display.gold_label.text == "Gold: 50" and display.reputation_label.text == "Reputation: 5", "wallet labels keep their Phase 2 format")
	_check(display.is_showing_delta() and display.delta_label.text == "+50 g  +5 rep", "payout delta '%s'" % display.delta_label.text)
	_check(display.rank_label.text == "Novice Courier  (10 to next)", "rank line '%s'" % display.rank_label.text)
	_check(is_equal_approx(display.rank_bar.value, 5.0 / 15.0), "rank bar at 5/15 (%.3f)" % display.rank_bar.value)
	_check(not tracker.visible, "tracker hides with no delivery in progress")
	await _frames(2)
	_check(prompt.label.text == "[E] Talk to Merchant Mira", "prompt returns to talk after the handover: '%s'" % prompt.label.text)
	await _close_dialogue()

	_behaviour("MerchantMira")._process(5.0)
	_check(_behaviour("MerchantMira").marker == M.NONE and not _behaviour("MerchantMira").marker_label.visible, "thank-you tick expires")
	display._process(10.0)
	_check(not display.is_showing_delta() and display.delta_label.text.is_empty(), "payout delta fades out")


func _test_q2_not_ready_and_rank_up() -> void:
	print("[Q2: not-ready feedback and rank up]")
	var mage := _npc("MageElowen")
	_check(manager.accept_quest(Q2) == QuestManager.AcceptResult.OK, "Q2 accepted")
	await _frames(2)
	_pickup_for(&"pkg_dragon_egg").interactable.interact(player)
	await _frames(2)
	_check(carrier.is_carrying() and carrier.get_package().get_package_id() == &"pkg_dragon_egg", "carrying the dragon egg")
	_check(hud.quest_tracker.header_label.text == "ACTIVE DELIVERY · STEP 2/3", "travel step header '%s'" % hud.quest_tracker.header_label.text)
	_check(_marker("MageElowen") == M.AWAITING, "Elowen's '?' stays dim until the clearing is reached")
	mage.interactable.interact(player)
	await _frames(1)
	var not_yet := _toast_index("Not yet: Carry the egg to the Forest Clearing")
	_check(not_yet >= 0 and hud.quest_notification.kind_history[not_yet] == QuestNotification.KIND_WARNING, "early handover explains the missing step")
	_check(carrier.is_carrying() and manager.get_status(Q2) == S.ACTIVE, "egg kept, Q2 still active")
	await _close_dialogue()

	var clearing := level.get_node("ForestEntrance/Markers/ForestClearingSpot/ForestClearing") as DestinationArea
	player.teleport_to(clearing.global_position)
	rig.snap_to_target()
	await _frames(6)
	_check(_marker("MageElowen") == M.DELIVER, "Elowen's '?' lights up inside the clearing")
	var rank_before := wallet.get_rank()
	mage.interactable.interact(player)
	await _frames(3)
	_check(manager.get_status(Q2) == S.REWARDED, "Q2 delivered")
	_check(rank_before == 0 and wallet.get_rank() == 1, "reputation %d promotes the courier to Apprentice" % wallet.reputation)
	var rank_toast := _toast_index("Rank up: Apprentice Courier!")
	var done := _toast_index("Delivery complete: The Dragon Egg")
	_check(rank_toast >= 0 and hud.quest_notification.kind_history[rank_toast] == QuestNotification.KIND_RANK, "rank-up toast posted")
	_check(done >= 0 and rank_toast > done, "rank-up toast follows the delivery toast")
	_check(hud.wallet_display.rank_label.text.begins_with("Apprentice Courier"), "wallet shows the new rank '%s'" % hud.wallet_display.rank_label.text)
	await _close_dialogue()


func _test_board_feedback() -> void:
	print("[Quest board feedback]")
	await _stand_near(board, board.global_position + Vector3(0, 0, 2))
	board_ui.open(board, player)
	await _frames(1)
	var button: Button = board_ui.accept_buttons.get(Q3)
	_check(button != null and not button.disabled, "Q3 can be accepted")
	if button != null:
		button.pressed.emit()
	await _frames(1)
	_check(manager.get_status(Q3) == S.ACCEPTED, "Q3 accepted from the board")
	_check(board_ui.feedback_label.text.contains("First: Pick up"), "board names the first step: '%s'" % board_ui.feedback_label.text)
	board_ui.close()
	await _frames(2)
	_check(hud.quest_tracker.header_label.text == "CONTRACT ACCEPTED · STEP 1/2", "Q3 header '%s'" % hud.quest_tracker.header_label.text)


func _test_hud_fits() -> void:
	print("[HUD fits]")
	var viewport := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var tracker := hud.quest_tracker.get_global_rect()
	var wallet_rect := hud.wallet_display.get_global_rect()
	_check(viewport.encloses(tracker) and viewport.encloses(wallet_rect), "tracker and wallet stay on screen")
	_check(not tracker.intersects(wallet_rect), "tracker and wallet do not overlap")
	var minimap := hud.get_node_or_null("Minimap")
	if minimap != null and minimap.get("compact") != null:
		_check(wallet_rect.end.y < (minimap.compact as Control).get_global_rect().position.y, "taller wallet still sits above the minimap")
