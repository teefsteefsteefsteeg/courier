extends SceneTree
## Real-village regression coverage for the unfinished tool/gathering loop.
## Uses an isolated save; tool timers are advanced deterministically after real physics
## settles the courier at each site. Never reads the player's save.

const SAVE_PATH := "user://phase6_tools_test_save.json"
var failures := 0
var passes := 0
var level: Node3D
var player: PlayerController
var user: ToolUser
var inventory: CourierInventory
var wallet: CourierWallet
var gathering: GatheringService


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	if ok:
		passes += 1
		print("PASS ", description)
	else:
		failures += 1
		printerr("FAIL ", description)


func frames(count: int = 6) -> void:
	for i in count:
		await physics_frame
	await process_frame


func equip(id: StringName) -> void:
	check(inventory.equip(id), "equip %s" % id)


func approach(site: ToolTarget) -> void:
	player.teleport_to(site.get_reach_point() + Vector3(1.0, 0.0, 1.0))
	await frames(12)


func finish() -> void:
	for i in 200:
		if not user.is_busy():
			return
		user._physics_process(0.1)
	check(false, "tool action finished within 20 simulated seconds")
	user.cancel()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).enabled = false
	root.add_child(level)
	current_scene = level
	await frames(20)
	player = level.get_node("Player") as PlayerController
	user = ToolUser.find_on(player)
	user.set_physics_process(false)
	inventory = CourierInventory.find(self)
	wallet = CourierWallet.find(self)
	gathering = GatheringService.find(self)
	var catalog := load("res://data/shops/toolwright.tres") as ShopCatalog
	test_generated_rod()
	wallet.add_gold(1000)
	check(catalog.items.size() == 6 and catalog.buys_materials, "Toolwright sells six tools and buys materials")
	for item in catalog.items:
		check(item.is_tool() and item.icon != null and item.held_model != null, "%s has tool type, icon and held model" % item.item_id)
		check(ShopService.buy(wallet, inventory, item) == ShopService.PurchaseResult.OK, "purchase %s" % item.item_id)
		check(ShopService.buy(wallet, inventory, item) == ShopService.PurchaseResult.ALREADY_OWNED, "duplicate %s refused" % item.item_id)
	var ids: Array[StringName] = []
	for node in get_nodes_in_group(ToolTarget.GROUP):
		check(node.target_id != &"" and not ids.has(node.target_id), "stable unique target id %s" % node.target_id)
		ids.append(node.target_id)
	await test_harvesting()
	await test_repairs()
	await test_fishing()
	test_trading(catalog)
	await test_save()
	root.remove_child(level)
	level.free()
	await frames(2)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("=== Phase 6 tools: %d passed, %d failed ===" % [passes, failures])
	quit(failures)


func test_generated_rod() -> void:
	var rod := (load("res://assets/generated/tools/fishing_rod.tscn") as PackedScene).instantiate() as Node3D
	var triangles := 0
	for mesh: MeshInstance3D in rod.find_children("*", "MeshInstance3D", true, false):
		triangles += mesh.mesh.get_faces().size() / 3
	check(triangles <= 2000, "Blender rod stays under 2000 triangles (%d)" % triangles)
	check(rod.get_node("BlenderModel").position == Vector3.ZERO and is_equal_approx(rod.get_node("Tip").position.y, 1.78), "Blender rod uses metre scale and grip-centred pivot along +Y")
	check(rod.get_node("WorldCollision/Shape").disabled and rod.get_node("WorldCollision").collision_layer == 0, "rod collision is provided and disabled while held")
	check(inventory.get_definition(&"fishing_rod").held_model.resource_path.begins_with("res://assets/generated/"), "playable fishing tool uses generated rod")
	rod.free()


func test_harvesting() -> void:
	var tree := level.get_node("ToolSites/GroveTree1") as HarvestNode
	await approach(tree)
	equip(&"miner_pickaxe")
	check(not user.begin(tree) and tree.is_available(), "wrong tool cannot fell a tree")
	equip(&"woodcutter_axe")
	check(user.begin(tree), "axe starts chopping")
	user._physics_process(0.01)
	user.cancel()
	check(tree.is_available() and inventory.get_material_count(&"wood") == 0 and player.input_enabled, "cancel before impact pays nothing and returns control")
	var wood := inventory.get_material_definition(&"wood")
	inventory.add_material(wood, CourierInventory.MAX_STACK)
	check(not user.begin(tree) and tree.complete(user).is_empty() and tree.is_available(), "full stack preserves harvest node and refuses work")
	inventory.remove_materials({&"wood": CourierInventory.MAX_STACK})
	check(user.begin(tree), "can retry after making room")
	finish()
	var count := inventory.get_material_count(&"wood")
	check(count >= tree.yield_min and count <= tree.yield_max, "tree pays its configured yield")
	check(not tree.is_available() and tree.depleted_visual.visible and not tree.standing_visual.visible, "felled tree swaps to stump")
	check(tree.complete(user).is_empty() and inventory.get_material_count(&"wood") == count, "depleted tree never pays twice")
	check(not user.begin(tree), "depleted target refuses another action")
	var time_now := Time.get_unix_time_from_system()
	gathering.clock = func() -> float: return time_now + 4000.0
	check(not gathering.is_depleted(tree.target_id) and tree.standing_visual.visible, "elapsed real time regrows tree and restores visual")
	gathering.clock = func() -> float: return Time.get_unix_time_from_system()
	check(user.begin(tree), "regrown tree can be worked")
	player.teleport_to(Vector3.ZERO)
	user._physics_process(0.1)
	check(not user.is_busy() and player.input_enabled and tree.is_available(), "leaving reach cancels without payout")
	for spec in [["ToolSites/QuarryRock1", &"miner_pickaxe", &"stone"], ["ToolSites/WillowmerePond/DigWest", &"garden_shovel", &"clay"]]:
		var site := level.get_node(spec[0]) as HarvestNode
		await approach(site)
		equip(spec[1])
		check(user.begin(site), "start %s" % site.display_name)
		finish()
		check(inventory.get_material_count(spec[2]) > 0 and not site.is_available(), "%s yields material and depletes" % site.display_name)
	await approach(tree)
	equip(&"woodcutter_axe")
	check(user.begin(tree), "start before forced equipment change")
	inventory.equip(&"miner_pickaxe")
	user._physics_process(0.1)
	check(not user.is_busy() and tree.is_available(), "equipment change cancels work")


func test_repairs() -> void:
	var jetty := level.get_node("ToolSites/WillowmerePond/Jetty") as RepairSite
	var spot := level.get_node("ToolSites/WillowmerePond/JettySpot") as FishingSpot
	check(not spot.is_available() and not spot.interactable.enabled, "broken jetty locks fishing spot")
	await approach(jetty)
	equip(&"carpenter_hammer")
	inventory.remove_materials({&"wood": inventory.get_material_count(&"wood")})
	check(not user.begin(jetty), "repair refuses missing materials")
	inventory.add_material(inventory.get_material_definition(&"wood"), 10)
	var gold := wallet.gold
	var rep := wallet.reputation
	check(user.begin(jetty), "funded jetty repair starts")
	finish()
	check(jetty.is_repaired() and inventory.get_material_count(&"wood") == 6, "repair takes exactly four wood")
	check(wallet.gold == gold + jetty.reward_gold and wallet.reputation == rep + jetty.reward_reputation, "repair pays configured gold and reputation")
	check(spot.is_available() and spot.interactable.enabled and not jetty.blockers[0].can_process(), "repair opens walkway and fishing spot")
	gold = wallet.gold
	check(jetty.complete(user).is_empty() and wallet.gold == gold and inventory.get_material_count(&"wood") == 6, "repeat repair consumes nothing and pays nothing")
	for spec in [["ToolSites/PumpkinFence", &"carpenter_hammer"], ["ToolSites/QuarryWall", &"mason_trowel"]]:
		var site := level.get_node(spec[0]) as RepairSite
		for id in site.materials:
			inventory.add_material(inventory.get_material_definition(id), site.materials[id])
		await approach(site)
		equip(spec[1])
		check(user.begin(site), "start %s repair" % site.display_name)
		finish()
		check(site.is_repaired(), "%s repaired" % site.display_name)


func fish_count() -> int:
	return inventory.get_material_count(&"pond_perch") + inventory.get_material_count(&"silver_trout") + inventory.get_material_count(&"golden_carp")


func test_fishing() -> void:
	equip(&"fishing_rod")
	player.teleport_to(Vector3.ZERO)
	await frames(12)
	check(not user.cast_from_bank(), "dry land refuses fishing")
	var spot := level.get_node("ToolSites/WillowmerePond/JettySpot") as FishingSpot
	await approach(spot)
	user.bite_wait_min = 0.2
	user.bite_wait_max = 0.2
	check(user.begin(spot), "repaired jetty allows casting")
	user.hook()
	check(not user.is_busy() and fish_count() == 0 and user.bobber == null, "early hook loses fish and clears props")
	check(user.begin(spot), "cast again after early hook")
	finish()
	check(fish_count() == 0 and user.fish_state == ToolUser.FishState.NONE, "missed bite yields no fish and ends")
	for attempt in 2:
		check(user.begin(spot), "repeat cast %d" % attempt)
		for i in 100:
			if user.fish_state == ToolUser.FishState.BITE:
				break
			user._physics_process(0.1)
		check(user.fish_state == ToolUser.FishState.BITE and user.bobber != null and user.line != null, "cast reaches bite with visible tackle")
		user.hook()
		check(user.fish_state == ToolUser.FishState.REELING, "hook enters reeling")
		for i in 100:
			user._physics_process(0.05)
			if user._caught:
				break
		var success: Array[bool] = []
		var listener := func(_t: ToolTarget, ok: bool, _m: String) -> void: success.append(ok)
		user.action_finished.connect(listener, CONNECT_ONE_SHOT)
		user.cancel()
		check(success == [true] and fish_count() == attempt + 1, "cancel after landing records success with exactly one catch")
		check(player.input_enabled and user.bobber == null and user.line == null, "fishing returns control and removes tackle")
	check(gathering.get_count(&"fish") == 2, "lifetime fish count matches catches")


func test_trading(catalog: ShopCatalog) -> void:
	var amount := inventory.get_material_count(&"wood")
	var gold := wallet.gold
	var armory := load("res://data/shops/armory.tres") as ShopCatalog
	check(ShopService.sell_material(wallet, inventory, armory, &"wood", amount) == 0 and wallet.gold == gold, "Armory refuses material sale")
	check(ShopService.sell_material(wallet, inventory, catalog, &"wood", amount + 1) == 0, "overselling refused")
	check(ShopService.sell_material(wallet, inventory, catalog, &"wood", -1) == 0, "negative sale refused")
	check(ShopService.sell_material(wallet, inventory, catalog, &"unknown", 1) == 0, "unknown material refused")
	var expected := amount * inventory.get_material_definition(&"wood").sell_price
	check(ShopService.sell_material(wallet, inventory, catalog, &"wood", amount) == expected, "Toolwright pays configured unit price")
	check(wallet.gold == gold + expected and inventory.get_material_count(&"wood") == 0, "sale transfers gold and removes materials")
	check(ShopService.sell_material(wallet, inventory, catalog, &"wood", amount) == 0, "cannot sell same stack twice")
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	check(shop.sell_all(&"stone") == 0, "closed shop refuses sales")
	var stall := level.get_node("ToolSites/ToolStall") as ToolStall
	var merchant := stall.merchant.get_node("ShopMerchant") as Merchant
	shop.open(merchant, player)
	check(shop.is_open() and shop.sell_rows.size() == 10, "Toolwright UI lists material and produce sales")
	check(shop.sell_all(&"stone") > 0 and inventory.get_material_count(&"stone") == 0, "shop sell button completes transaction")
	shop.close()


func test_save() -> void:
	await frames()
	var save := SaveGame.find(self)
	save.path = SAVE_PATH
	var snapshot := JSON.stringify(save.to_dict())
	check(save.save_game(), "save tools, materials and world state to disk")
	inventory.from_dict({})
	gathering.from_dict({})
	wallet.restore(0, 0)
	check(save.load_game(), "load saved tool progress")
	check(JSON.stringify(save.to_dict()) == snapshot, "disk round trip preserves complete state")
	var jetty := level.get_node("ToolSites/WillowmerePond/Jetty") as RepairSite
	check(jetty.is_repaired() and jetty.repaired_visual.visible, "load reapplies repaired world visual")
	check(inventory.get_equipped_tool().item_id == &"fishing_rod", "load restores held tool")
	gathering.from_dict({})
	check(not jetty.is_repaired() and jetty.damaged_visual.visible, "legacy save without gathering starts unrepaired")
