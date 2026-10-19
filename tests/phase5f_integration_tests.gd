extends SceneTree
## Phase 5F integration: the building/visual Armory and the gameplay/UI shop working
## together in the real village. Walk to Weaponsmith Brenna's shop front, the prompt and
## world keycap, the shop window opening from her (Armory.shop_requested still fires),
## a purchase and equip, the minimap label, and the HUD staying clear at the Armory.
## Run headless from the project root:
##   godot --headless --path . --script res://tests/phase5f_integration_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"

var _failures: int = 0
var _passes: int = 0


func _initialize() -> void:
	_run.call_deferred()


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
	# process_frame fires before that frame's _process callbacks; wait one more so UI
	# that updates in _process (the world keycap) has caught up.
	await process_frame
	await process_frame


func _run() -> void:
	# The game's 1600x900 view (headless defaults to a square viewport, which frames the
	# Armory differently from the real window).
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	var level := (load(VILLAGE) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	current_scene = level
	var player := level.get_node("Player") as PlayerController
	var rig := level.get_node("IsoCameraRig") as IsoCameraRig
	var integration := level.get_node_or_null("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	if integration != null:
		integration.simulate_enemies = false
	await _frames(20)
	var armories := level.find_children("*", "Armory", true, false)
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	var hud := level.get_node("GameplayHUD") as GameplayHUD
	var wallet := CourierWallet.find(self)
	var inventory := CourierInventory.find(self)

	print("[Armory in the village]")
	_check(armories.size() == 1, "the village has the Armory")
	var armory := armories[0] as Armory
	var brenna := armory.merchant
	_check(brenna != null and brenna.npc_name == "Weaponsmith Brenna", "Weaponsmith Brenna is behind the counter")
	var merchant := brenna.get_node_or_null("ShopMerchant") as Merchant
	_check(merchant != null and merchant.get_catalog() == load("res://data/shops/armory.tres"), "Brenna sells the Armory catalog")

	print("[Walking up to the counter]")
	player.teleport_to(armory.get_shop_front().global_position)
	rig.snap_to_target()
	await _frames(40)
	_check(player.interaction.focused == brenna.interactable, "Brenna is focused at the shop front")
	_check(prompt.label.text == "[E] Browse wares of Weaponsmith Brenna", "prompt '%s'" % prompt.label.text)
	_check(prompt.world_badge.visible, "world keycap shown beside Brenna")
	var requests := []
	armory.shop_requested.connect(func(interactor: Node) -> void: requests.append(interactor))
	player.interaction.try_interact(player)
	await _frames(2)
	_check(shop.is_open() and shop.merchant == merchant and shop.title_label.text == "Weaponsmith Brenna", "talking to Brenna opens her shop")
	_check(requests == [player], "Armory.shop_requested still fires for the visual layer")
	var wares := (load("res://data/shops/armory.tres") as ShopCatalog).items.size()
	_check(shop.rows.size() == wares and not player.input_enabled, "all %d wares listed, courier paused" % wares)
	var dialogue := level.get_node("DialogueBox") as DialogueBox
	_check(not dialogue.is_open(), "her dialogue line does not stay under the shop")

	print("[Buying and equipping]")
	_check(wallet.gold == 0 and _button(shop, &"iron_sword").disabled, "no gold in a headless run: Buy disabled")
	wallet.add_gold(150)
	await _frames(1)
	shop.activate(&"iron_sword")
	await _frames(1)
	_check(wallet.gold == 0 and inventory.has_item(&"iron_sword"), "bought the Iron Sword for 150")
	var combat := player.get_node("Combat") as CombatController
	var base := combat.bolt_damage
	shop.activate(&"iron_sword")
	await _frames(1)
	# Since weapon switching, a sword is a fast melee weapon (docs/PHASE5F_WEAPON_SWITCHING.md).
	_check(inventory.is_equipped(&"iron_sword") and combat.get_attack_style() == CombatController.AttackStyle.FAST_MELEE and is_equal_approx(combat.melee_damage, 20.0) and is_equal_approx(combat.bolt_damage, base),
			"equipped: the iron sword swings for %.1f (bolt stays %.1f)" % [combat.melee_damage, combat.bolt_damage])
	shop.close()
	await _frames(2)
	_check(not shop.is_open() and player.input_enabled, "shop closed, courier moves again")

	print("[HUD at the Armory]")
	var map := hud.get_node("Minimap")
	map.refresh_objective()
	var brenna_marker: Dictionary = map.model.get_marker(map.model.find_id_for_node(brenna))
	_check(not brenna_marker.is_empty() and brenna_marker["label"] == "Weaponsmith Brenna", "Brenna is on the minimap by name")
	_check(hud.movement_guide.visible, "WASD guide visible")
	var badge := prompt.world_badge.get_global_rect()
	var hits: PackedStringArray = []
	for node in get_nodes_in_group(InputPrompt.AVOID_GROUP):
		var control := node as Control
		if control.is_visible_in_tree() and prompt.world_badge.visible and control.get_global_rect().intersects(badge):
			hits.append(control.name)
	_check(hits.is_empty(), "world keycap clear of the HUD at the counter %s" % hits)

	print("\n=== Phase 5F integration tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


func _button(shop: ShopUI, item_id: StringName) -> Button:
	return shop.rows[item_id]["button"] as Button
