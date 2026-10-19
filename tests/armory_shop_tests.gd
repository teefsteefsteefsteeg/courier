extends SceneTree
## Armory shop gameplay: catalog data, purchase rules (gold out, item in, insufficient
## gold, duplicates), the shop window through a merchant counter and a merchant NPC,
## equipping and the combat stats it changes, quest gold rewards without duplicates,
## the one-time development starting gold, and saving / loading all of it.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/armory_shop_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const CATALOG := "res://data/shops/armory.tres"
const COUNTER := "res://scenes/gameplay/shop/merchant_counter.tscn"
const SAVE_PATH := "user://armory_shop_test_save.json"
const PRICES := {
	&"wooden_sword": 50, &"iron_sword": 150, &"steel_sword": 300,
	&"battle_axe": 400, &"magic_staff": 500, &"wooden_shield": 100, &"hunting_bow": 250,
}
const Q1 := &"q001_first_delivery"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var wallet: CourierWallet
var inventory: CourierInventory
var manager: QuestManager
var save: SaveGame
var equipment: EquipmentStats
var combat: CombatController
var shop: ShopUI
var prompt: InteractionPrompt
var catalog: ShopCatalog


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	catalog = load(CATALOG) as ShopCatalog
	_test_catalog()
	await _test_purchase_rules()

	await _load_village()
	_test_no_dev_gold_in_tests()
	_test_dev_starting_gold()
	await _test_shop_window()
	await _test_equipment()
	await _test_merchant_npc()
	await _test_quest_reward_gold()
	await _test_persistence()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("\n=== Armory shop tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _load_village() -> void:
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	wallet = CourierWallet.find(self)
	inventory = CourierInventory.find(self)
	manager = QuestManager.find(self)
	save = SaveGame.find(self)
	equipment = level.get_node("GameplayServices/EquipmentStats") as EquipmentStats
	combat = player.get_node("Combat") as CombatController
	shop = level.get_node("GameplayHUD/ShopUI") as ShopUI
	prompt = level.get_node("InteractionPrompt")
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	save.path = SAVE_PATH
	await _frames(20)


func _row_button(item_id: StringName) -> Button:
	return shop.rows[item_id]["button"] as Button


func _character() -> KayKitCharacter:
	return player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter


# --- data and rules ------------------------------------------------------------

func _test_catalog() -> void:
	print("[Armory catalog]")
	# Six items from the brief plus the Hunting Bow added with weapon switching.
	_check(catalog != null and catalog.items.size() == 7, "seven items for sale")
	var prices := {}
	var missing_icons: PackedStringArray = []
	for item in catalog.items:
		prices[item.item_id] = item.price
		if item.icon == null or item.icon.get_size() != Vector2(32, 32):
			missing_icons.append(item.item_id)
	_check(prices == PRICES, "test prices match the brief %s" % prices)
	_check(missing_icons.is_empty(), "every item has a 32x32 icon %s" % missing_icons)
	_check(catalog.get_item(&"wooden_shield").slot == ItemDefinition.Slot.OFF_HAND and catalog.get_item(&"iron_sword").slot == ItemDefinition.Slot.MAIN_HAND, "shield is off-hand, weapons main-hand")
	_check(catalog.get_item(&"magic_staff").get_stat_lines() == PackedStringArray(["+10 bolt damage", "25% faster casting", "+6 m bolt range"]), "staff stat lines %s" % catalog.get_item(&"magic_staff").get_stat_lines())
	_check(catalog.get_item(&"iron_sword").held_model != null and catalog.get_item(&"magic_staff").held_model != null, "swords and staff have a held model")


func _test_purchase_rules() -> void:
	print("[Purchase rules]")
	var test_wallet := CourierWallet.new()
	var test_inventory := CourierInventory.new()
	root.add_child(test_wallet)
	root.add_child(test_inventory)
	var sword := catalog.get_item(&"iron_sword")
	_check(ShopService.buy(test_wallet, test_inventory, sword) == ShopService.PurchaseResult.NOT_ENOUGH_GOLD and test_wallet.gold == 0 and not test_inventory.has_item(sword.item_id),
			"no gold: refused, nothing changes")
	test_wallet.add_gold(149)
	_check(ShopService.buy(test_wallet, test_inventory, sword) == ShopService.PurchaseResult.NOT_ENOUGH_GOLD and test_wallet.gold == 149, "one gold short: refused, gold kept")
	_check(ShopService.result_text(ShopService.PurchaseResult.NOT_ENOUGH_GOLD, sword, test_wallet) == "Not enough gold: Iron Sword costs 150, you have 149.", "refusal names the price")
	test_wallet.add_gold(1)
	_check(ShopService.buy(test_wallet, test_inventory, sword) == ShopService.PurchaseResult.OK and test_wallet.gold == 0 and test_inventory.has_item(sword.item_id), "exact gold: bought, 150 deducted, item added")
	test_wallet.add_gold(500)
	_check(ShopService.buy(test_wallet, test_inventory, sword) == ShopService.PurchaseResult.ALREADY_OWNED and test_wallet.gold == 500, "buying it twice is refused")
	_check(not test_wallet.spend_gold(501) and not test_wallet.spend_gold(-5) and test_wallet.gold == 500, "spend_gold refuses overdrafts and negatives")
	_check(not test_inventory.equip(&"steel_sword"), "cannot equip an item you do not own")
	test_wallet.queue_free()
	test_inventory.queue_free()
	await _frames(1)


func _test_no_dev_gold_in_tests() -> void:
	print("[Starting gold]")
	_check(not DevMode.is_enabled(), "headless test runs are not development mode")
	_check(wallet.gold == 0 and not save.starting_gold_granted, "so the courier starts with 0 gold here (%d)" % wallet.gold)
	_check(not save.enabled, "the save file is not touched by headless runs")


func _test_dev_starting_gold() -> void:
	_check(not save.grant_dev_starting_gold(false), "no grant outside development mode")
	_check(save.grant_dev_starting_gold(true) and wallet.gold == SaveGame.DEV_STARTING_GOLD, "development mode grants 500 gold")
	_check(not save.grant_dev_starting_gold(true) and wallet.gold == 500, "but only once")


# --- shop window -----------------------------------------------------------------

func _test_shop_window() -> void:
	print("[Shop window through a merchant counter]")
	var counter := (load(COUNTER) as PackedScene).instantiate() as Node3D
	level.add_child(counter)
	counter.global_position = Vector3(0, 0, 4)
	player.teleport_to(Vector3(0, 0, 5.2))
	rig.snap_to_target()
	await _frames(8)
	_check(player.interaction.focused == counter.get_node("Interactable"), "courier focuses the counter")
	_check(prompt.label.text == "[E] Browse Willowmere Armory", "prompt '%s'" % prompt.label.text)
	player.interaction.try_interact(player)
	await _frames(1)
	_check(shop.is_open() and shop.merchant == counter.get_node("Merchant"), "interacting opens the shop")
	_check(not player.input_enabled and shop.is_in_group(QuestJournal.MODAL_GROUP), "shop is modal and pauses the courier")
	_check(shop.rows.size() == catalog.items.size(), "one row per item (%d)" % shop.rows.size())
	_check(shop.gold_label.text == "Gold: 500", "gold shown '%s'" % shop.gold_label.text)
	_check((shop.rows[&"battle_axe"]["price"] as Label).text == "400 g", "prices shown")
	var icon := (shop.rows[&"magic_staff"]["row"] as Control).find_children("*", "TextureRect", true, false)[0] as TextureRect
	_check(icon.texture == catalog.get_item(&"magic_staff").icon and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and icon.custom_minimum_size == Vector2(64, 64), "icons drawn 2x with nearest filtering")
	var journal := level.get_node("QuestJournal") as QuestJournal
	journal.open()
	_check(not journal.is_open(), "journal does not open over the shop")

	_check(not _row_button(&"magic_staff").disabled and _row_button(&"magic_staff").text == "Buy", "staff affordable at 500")
	shop.activate(&"magic_staff")
	await _frames(1)
	_check(wallet.gold == 0 and inventory.has_item(&"magic_staff"), "bought the staff: 500 deducted")
	_check(shop.gold_label.text == "Gold: 0" and _row_button(&"magic_staff").text == "Equip", "window updates: gold 0, staff Equip")
	_check(shop.feedback_label.text.begins_with("Bought Magic Staff."), "feedback '%s'" % shop.feedback_label.text)
	var sword_button := _row_button(&"wooden_sword")
	_check(sword_button.disabled and (shop.rows[&"wooden_sword"]["status"] as Label).text == "Need 50 more gold", "with 0 gold the sword is disabled and says why")
	shop.activate(&"wooden_sword")
	_check(not inventory.has_item(&"wooden_sword") and wallet.gold == 0, "pressing a disabled Buy does nothing")

	print("[Closing the shop]")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	Input.flush_buffered_events()
	await _frames(2)
	_check(not shop.is_open() and not shop.is_in_group(QuestJournal.MODAL_GROUP), "Escape closes the shop")
	_check(player.input_enabled, "courier input restored")
	counter.queue_free()
	await _frames(1)


func _test_equipment() -> void:
	print("[Equipment changes combat stats]")
	var base_damage := equipment.get_base_stat("bolt_damage")
	var base_cooldown := equipment.get_base_stat("bolt_cooldown")
	var base_range := equipment.get_base_stat("bolt_range")
	var base_shield := equipment.get_base_stat("shield_max_durability")
	_check(is_equal_approx(combat.bolt_damage, base_damage) and base_damage > 0.0, "unequipped: base bolt damage %.1f" % base_damage)
	shop.open(_first_merchant_or_new(), player)
	await _frames(1)
	shop.activate(&"magic_staff")
	await _frames(1)
	_check(inventory.is_equipped(&"magic_staff") and _row_button(&"magic_staff").text == "Unequip", "staff equipped from the shop")
	_check(is_equal_approx(combat.bolt_damage, base_damage + 10.0) and is_equal_approx(combat.bolt_cooldown, base_cooldown * 0.75) and is_equal_approx(combat.bolt_range, base_range + 6.0),
			"staff: damage %.1f, cooldown %.3f, range %.1f" % [combat.bolt_damage, combat.bolt_cooldown, combat.bolt_range])
	var held := _character().get_held_item_node()
	_check(held != null, "the staff appears in the courier's hand")
	_check(combat.try_magic_bolt(Vector3.RIGHT), "cast a bolt")
	var bolts := level.find_children("*", "CombatProjectile", true, false)
	_check(not bolts.is_empty() and is_equal_approx((bolts[-1] as CombatProjectile).damage, base_damage + 10.0), "the bolt carries the equipped damage")

	wallet.add_gold(100)
	await _frames(1)
	shop.activate(&"wooden_shield")
	shop.activate(&"wooden_shield")
	await _frames(1)
	_check(inventory.is_equipped(&"wooden_shield") and inventory.is_equipped(&"magic_staff"), "shield (off-hand) and staff (main hand) equipped together")
	_check(is_equal_approx(combat.shield_max_durability, base_shield + 25.0), "shield adds package-shield durability (%.1f)" % combat.shield_max_durability)
	shop.activate(&"magic_staff")
	await _frames(1)
	_check(not inventory.is_equipped(&"magic_staff") and is_equal_approx(combat.bolt_damage, base_damage) and is_equal_approx(combat.bolt_cooldown, base_cooldown) and is_equal_approx(combat.bolt_range, base_range),
			"unequipping restores the base bolt stats exactly")
	_check(_character().get_held_item_node() == null, "empty hand without a weapon")
	shop.activate(&"magic_staff")
	await _frames(1)
	_check(inventory.is_equipped(&"magic_staff"), "re-equipped for the save test")
	shop.close()
	await _frames(2)


func _first_merchant_or_new() -> Merchant:
	var counter := (load(COUNTER) as PackedScene).instantiate() as Node3D
	level.add_child(counter)
	counter.global_position = Vector3(30, 0, 30)
	return counter.get_node("Merchant") as Merchant


func _test_merchant_npc() -> void:
	print("[Merchant on an NPC]")
	var pip := level.get_node("NPCs/VillagerPip") as NPC
	var merchant := Merchant.new()
	merchant.catalog = catalog
	pip.add_child(merchant)
	await _frames(1)
	player.teleport_to(pip.global_position + Vector3(1.2, 0, 0))
	rig.snap_to_target()
	await _frames(8)
	_check(prompt.label.text == "[E] Browse wares of Villager Pip", "NPC prompt '%s'" % prompt.label.text)
	player.interaction.try_interact(player)
	await _frames(2)
	var dialogue := level.get_node("DialogueBox") as DialogueBox
	_check(shop.is_open() and shop.title_label.text == "Villager Pip", "talking to the NPC opens their shop")
	_check(not dialogue.is_open(), "the NPC's dialogue line does not stay under the shop")
	shop.close()
	merchant.queue_free()
	await _frames(2)


# --- quests and saving ---------------------------------------------------------------

func _test_quest_reward_gold() -> void:
	print("[Delivery quests reward gold once]")
	var gold_before := wallet.gold
	_check(manager.accept_quest(Q1) == QuestManager.AcceptResult.OK, "Q1 accepted")
	manager.notify_talked_to(&"postmaster")
	manager.notify_package_picked_up(&"pkg_ordinary_parcel")
	var parcel := PackageInstance.new(load("res://data/packages/pkg_ordinary_parcel.tres"))
	_check(manager.try_deliver(&"village_merchant", parcel) == QuestManager.DeliveryResult.OK, "Q1 delivered")
	_check(wallet.gold == gold_before + 50, "delivery pays 50 gold (%d -> %d)" % [gold_before, wallet.gold])
	_check(not manager.grant_reward(Q1) and wallet.gold == gold_before + 50, "the reward cannot be paid twice")
	_check(manager.accept_quest(Q1) != QuestManager.AcceptResult.OK, "a delivered contract cannot be taken again")


func _test_persistence() -> void:
	print("[Save and load]")
	var expected_gold := wallet.gold
	var expected_reputation := wallet.reputation
	_check(save.save_game() and FileAccess.file_exists(SAVE_PATH), "saved to %s" % SAVE_PATH)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_check(data.get("version") == SaveGame.VERSION and data["flags"]["starting_gold_granted"] == true, "save has a version and the starting-gold flag")
	_check(Array(data["inventory"]["owned"]) == ["magic_staff", "wooden_shield"] and data["inventory"]["equipped"] == {"MAIN_HAND": "magic_staff", "OFF_HAND": "wooden_shield"}, "save lists owned and equipped items %s" % [data["inventory"]])
	_check(data["quests"].has(String(Q1)) and data["quests"][String(Q1)]["status"] == "REWARDED", "save records the delivered contract")

	# A fresh session: new village, then load.
	level.queue_free()
	await _frames(3)
	await _load_village()
	_check(wallet.gold == 0 and inventory.get_owned_ids().is_empty() and manager.get_status(Q1) == QuestState.Status.AVAILABLE, "new session starts empty before loading")
	var base_damage := equipment.get_base_stat("bolt_damage")
	_check(save.load_game(), "save loaded")
	await _frames(2)
	_check(wallet.gold == expected_gold and wallet.reputation == expected_reputation, "gold %d and reputation %d restored" % [wallet.gold, wallet.reputation])
	_check(inventory.has_item(&"magic_staff") and inventory.has_item(&"wooden_shield") and inventory.is_equipped(&"magic_staff") and inventory.is_equipped(&"wooden_shield"), "items and equipment restored")
	_check(is_equal_approx(combat.bolt_damage, base_damage + 10.0) and _character().get_held_item_node() != null, "equipment stats and held staff re-applied (%.1f)" % combat.bolt_damage)
	_check(manager.get_status(Q1) == QuestState.Status.REWARDED and not manager.grant_reward(Q1) and wallet.gold == expected_gold, "delivered contract stays delivered and is not paid again")
	_check(manager.can_accept(Q1) == QuestManager.AcceptResult.NOT_AVAILABLE, "and is not offered again")
	_check(save.starting_gold_granted and not save.grant_dev_starting_gold(true) and wallet.gold == expected_gold, "starting gold is not granted again after loading")
	var hud := level.get_node("GameplayHUD") as GameplayHUD
	_check(hud.wallet_display.gold_label.text == "Gold: %d" % expected_gold and not hud.wallet_display.is_showing_delta(), "wallet display shows the loaded gold without a payout delta")

	print("[Autosave]")
	FileAccess.open(SAVE_PATH, FileAccess.WRITE).store_string("{}")
	save.enabled = true
	save._watch()
	wallet.add_gold(7)
	await create_timer(save.autosave_delay + 0.3).timeout
	var autosaved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	_check(int(autosaved.get("wallet", {}).get("gold", -1)) == expected_gold + 7, "a gold change is autosaved (%s)" % autosaved.get("wallet", {}))
	FileAccess.open(SAVE_PATH, FileAccess.WRITE).store_string("not json")
	_check(not save.load_game(), "a corrupt save is ignored, not applied")
	save.enabled = false
