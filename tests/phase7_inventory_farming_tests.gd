extends SceneTree
## Phase 7, Milestone B: the redesigned inventory window ([Q] switches Weapons & Gear and
## Tools & Goods while it is open, enhancement levels shown, one inventory) and the
## courier's garden (seeds from the Toolwright, beds near the spawn point, growth stages on
## a play-time clock, harvest, save/load, no double harvest), plus the chopping tree and ore
## rock beside the post office.
##   godot --headless --path . --script res://tests/phase7_inventory_farming_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"
const PARCEL := "res://data/packages/pkg_ordinary_parcel.tres"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var wallet: CourierWallet
var farm: FarmService
var equipment: EquipmentUI
var combat: CombatController


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase7_inventory_tests.json"
	root.add_child(level)
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	wallet = CourierWallet.find(self)
	farm = FarmService.find(self)
	equipment = level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	combat = CombatController.find_on(player)
	await _frames(20)

	await _test_inventory_views()
	await _test_q_does_not_raise_shield()
	_test_enhancement()
	await _test_enhancement_display()
	_test_seed_shop()
	_test_garden_layout()
	await _test_planting_and_growth()
	_test_harvest_rules()
	_test_farm_save()
	_test_gathering_near_spawn()

	print("\n=== Phase 7 inventory and farming tests: %d passed, %d failed ===" % [_passes, _failures])
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


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


# --- inventory ---------------------------------------------------------------

func _test_inventory_views() -> void:
	print("[Inventory views]")
	for id in [&"iron_sword", &"wooden_shield", &"woodcutter_axe"]:
		inventory.add_item(inventory.get_definition(id))
	await _press(&"toggle_equipment")
	_check(equipment.is_open() and equipment.view == EquipmentUI.View.WEAPONS, "Tab opens the inventory on Weapons & Gear")
	_check(equipment.title_label.text == "Weapons & Gear" and equipment.switch_hint.text == "[Q] Tools & Goods", "the header names the view and says [Q] switches (%s)" % equipment.switch_hint.text)
	var panel_rect := equipment.panel.get_global_rect()
	_check(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(panel_rect) and panel_rect.size.x > 900, "the window fits the screen (%s)" % panel_rect)
	_check((equipment.rows[&"iron_sword"]["row"] as Control).is_visible_in_tree() and not (equipment.rows[&"woodcutter_axe"]["row"] as Control).is_visible_in_tree(), "weapons show, tools are on the other view")
	await _press(&"quick_switch_tool")
	_check(equipment.view == EquipmentUI.View.TOOLS and equipment.title_label.text == "Tools & Goods", "[T] switches to Tools & Goods")
	_check((equipment.rows[&"woodcutter_axe"]["row"] as Control).is_visible_in_tree() and (equipment.material_rows[&"wheat_seeds"]["cell"] as Control).is_visible_in_tree(), "tools, seeds and materials show there")
	_check(equipment.selected_id == &"woodcutter_axe", "the selection follows the view (%s)" % equipment.selected_id)
	await _press(&"quick_switch_tool")
	_check(equipment.view == EquipmentUI.View.WEAPONS, "[T] switches back")
	(equipment.tab_buttons[1] as Button).pressed.emit()
	_check(equipment.view == EquipmentUI.View.TOOLS, "the side tab switches too")
	# One inventory: the window lists exactly what CourierInventory registers.
	_check(equipment.rows.size() == inventory.get_all_definitions().size() and equipment.material_rows.size() == inventory.get_all_materials().size(), "every item and material comes from CourierInventory")
	await _press(&"toggle_equipment")
	_check(not equipment.is_open() and player.input_enabled, "Q closes it and returns control")


func _test_q_does_not_raise_shield() -> void:
	print("[T while the inventory is open; R raises the shield]")
	var carrier := PackageCarrier.find_on(player)
	carrier.pick_up(PackageInstance.new(load(PARCEL)))
	inventory.equip(&"iron_sword")
	await _frames(2)
	equipment.open()
	await _frames(2)
	var view_before := equipment.view
	await _press(&"quick_switch_tool")
	_check(equipment.view != view_before, "T is taken by the inventory (switches its view)")
	_check(inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) == inventory.get_definition(&"iron_sword"), "T does not swap sword and tool while the inventory is open")
	await _press(&"package_shield")
	_check(not combat.is_shield_active(), "the Package Shield does not rise while the inventory is open")
	equipment.close()
	await _frames(3)
	await _press(&"package_shield")
	_check(combat.is_shield_active(), "with the window closed, R raises the Package Shield")
	await _press(&"package_shield")
	carrier.drop_package()
	await _frames(2)


func _test_enhancement() -> void:
	print("[Enhancement levels]")
	_check(inventory.get_enhancement(&"iron_sword") == 0, "items start at +0")
	_check(inventory.set_enhancement(&"iron_sword", 3) and inventory.get_enhancement(&"iron_sword") == 3, "an owned weapon can be +3")
	_check(inventory.set_enhancement(&"wooden_shield", 9) and inventory.get_enhancement(&"wooden_shield") == Enhancement.MAX_LEVEL, "levels are capped at +5")
	_check(not inventory.set_enhancement(&"steel_sword", 2) and inventory.get_enhancement(&"steel_sword") == 0, "an unowned item cannot be enhanced")
	var saved := inventory.to_dict()
	inventory.from_dict({})
	_check(inventory.get_enhancement(&"iron_sword") == 0, "clearing the inventory clears levels")
	inventory.from_dict(saved)
	_check(inventory.get_enhancement(&"iron_sword") == 3 and inventory.get_enhancement(&"wooden_shield") == 5, "levels survive save and load")
	_check(Enhancement.level_color(1).is_equal_approx(Enhancement.COLORS[1]) and Enhancement.TIER_NAMES[5] == "Golden", "+1 silver .. +5 golden")


func _test_enhancement_display() -> void:
	equipment.open()
	await _frames(2)
	equipment.select_item(&"iron_sword")
	var badge := equipment.rows[&"iron_sword"]["badge"] as Label
	_check(badge.text == "+3" and badge.get_theme_color(&"font_color").is_equal_approx(Enhancement.level_color(3)), "the item cell shows +3 in blue")
	_check(equipment._detail_stars.text.begins_with("Enhancement  ★★★☆☆"), "the details show the stars (%s)" % equipment._detail_stars.text)
	_check((equipment.rows[&"steel_sword"]["badge"] as Label).text == "", "unenhanced items have no badge")
	equipment.close()
	await _frames(2)


# --- farming -----------------------------------------------------------------

func _test_seed_shop() -> void:
	print("[Seeds from the Toolwright]")
	var catalog := load("res://data/shops/toolwright.tres") as ShopCatalog
	var wheat := inventory.get_material_definition(&"wheat_seeds")
	_check(catalog.sells_materials.size() == 3 and catalog.sells_materials.has(wheat), "the Toolwright sells three kinds of seed")
	wallet.restore(0, 0)
	_check(ShopService.buy_material(wallet, inventory, catalog, wheat, 1) == 0 and inventory.get_material_count(&"wheat_seeds") == 0, "no gold, no seeds")
	wallet.restore(20, 0)
	_check(ShopService.buy_material(wallet, inventory, catalog, wheat, 5) == 5 and wallet.gold == 15 and inventory.get_material_count(&"wheat_seeds") == 5, "5 wheat seeds for 5 gold")
	var armory := load("res://data/shops/armory.tres") as ShopCatalog
	_check(ShopService.buy_material(wallet, inventory, armory, wheat, 1) == 0, "the Armory sells no seeds")
	_check(ShopService.sell_material(wallet, inventory, catalog, &"wheat_seeds", 1) == 0, "seeds cannot be sold back")


func _test_garden_layout() -> void:
	print("[The garden]")
	var plots := level.find_children("*", "FarmPlot", true, false)
	_check(plots.size() == 4, "four garden beds (%d)" % plots.size())
	var spawn := Vector3(-15, 0, -5.6)
	var ids := {}
	for plot: FarmPlot in plots:
		ids[plot.plot_id] = true
	_check(ids.size() == 4, "each bed has its own id")
	_check(plots.all(func(p: FarmPlot) -> bool: return p.global_position.distance_to(spawn) < 20.0), "the beds are near the spawn point")
	_check(plots.all(func(p: FarmPlot) -> bool: return p.interactable != null and p.interactable.collision_layer == 8), "every bed can be interacted with")


func _test_planting_and_growth() -> void:
	print("[Planting and growing]")
	var plot := level.get_node("ToolSites/CourierGarden/Plot1") as FarmPlot
	var empty := level.get_node("ToolSites/CourierGarden/Plot2") as FarmPlot
	inventory.remove_materials({&"wheat_seeds": inventory.get_material_count(&"wheat_seeds")})
	_check(plot.get_interaction_prompt(player).contains("buy seeds"), "an empty bed without seeds says where to get them")
	plot.interactable.interact(player)
	_check(farm.is_empty(plot.plot_id), "nothing is planted without seeds")
	inventory.add_material(inventory.get_material_definition(&"wheat_seeds"), 2)
	_check(plot.get_interaction_prompt(player) == "Plant Wheat Seeds (2)", "with seeds the bed offers to plant them (%s)" % plot.get_interaction_prompt(player))
	plot.interactable.interact(player)
	_check(not farm.is_empty(plot.plot_id) and inventory.get_material_count(&"wheat_seeds") == 1, "planting takes exactly one seed")
	_check(farm.plant(plot.plot_id, &"wheat", inventory) == FarmService.PlantResult.OCCUPIED and inventory.get_material_count(&"wheat_seeds") == 1, "a planted bed refuses more seed")
	await _frames(2)
	_check(farm.get_stage(plot.plot_id) == 0 and plot.get_plant_count() == 9, "stage 0: nine seedlings")
	var crop := farm.get_crop(&"wheat")
	var sizes: Array[float] = []
	for stage in crop.stage_count:
		farm.advance(crop.stage_seconds)
		await _frames(2)
		var holder := plot.plants.get_child(0) as Node3D
		sizes.append(holder.scale.x)
	_check(farm.get_stage(plot.plot_id) == crop.stage_count and farm.is_ripe(plot.plot_id), "after %d s the wheat is ripe" % int(crop.get_grow_seconds()))
	_check(sizes[0] < sizes[1] and sizes[1] < sizes[2], "the plants grow through the stages %s" % [sizes])
	_check(plot.get_interaction_prompt(player) == "Harvest Wheat", "a ripe bed offers the harvest")
	# Preferred seed from the inventory: carrots are planted before wheat.
	inventory.add_material(inventory.get_material_definition(&"carrot_seeds"), 1)
	farm.set_preferred_seed(&"carrot_seeds")
	_check(empty.get_seed_choice(player).crop_id == &"carrot", "the seed picked in the inventory is planted first")


func _test_harvest_rules() -> void:
	print("[Harvest]")
	var plot_id := &"garden_plot_1"
	var plot := level.get_node("ToolSites/CourierGarden/Plot1") as FarmPlot
	var before := inventory.get_material_count(&"wheat")
	plot.interactable.interact(player)
	var gained := inventory.get_material_count(&"wheat") - before
	var crop := farm.get_crop(&"wheat")
	_check(gained >= crop.yield_min and gained <= crop.yield_max, "harvesting gives %d wheat" % gained)
	_check(farm.is_empty(plot_id), "the bed is empty again")
	_check(farm.harvest(plot_id, inventory) == 0 and inventory.get_material_count(&"wheat") == before + gained, "a bed cannot be harvested twice")
	farm.plant(plot_id, &"wheat", inventory)
	_check(farm.harvest(plot_id, inventory) == 0 and not farm.is_empty(plot_id), "an unripe crop cannot be harvested")
	var catalog := load("res://data/shops/toolwright.tres") as ShopCatalog
	var gold := wallet.gold
	var paid := ShopService.sell_material(wallet, inventory, catalog, &"wheat", gained)
	_check(paid == gained * 2 and wallet.gold == gold + paid, "the Toolwright buys wheat")


func _test_farm_save() -> void:
	print("[Saving the garden]")
	var plot_id := &"garden_plot_1"
	farm.advance(45.0)
	var stage := farm.get_stage(plot_id)
	var save := SaveGame.find(self)
	var data := save.to_dict()
	_check(data.has("farming") and (data["farming"]["plots"] as Dictionary).has(String(plot_id)), "the save has the garden")
	farm.from_dict({})
	_check(farm.is_empty(plot_id), "clearing the farm empties the bed")
	save.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(farm.get_stage(plot_id) == stage and farm.get_planted_crop(plot_id).crop_id == &"wheat", "load restores the crop at its stage (%d)" % stage)
	# Growth runs on saved play time, not the system clock: an edited save cannot ripen it.
	var edited: Dictionary = JSON.parse_string(JSON.stringify(data))
	edited["farming"]["plots"][String(plot_id)]["planted"] = 1.0e9
	farm.from_dict(edited["farming"])
	_check(farm.get_stage(plot_id) == 0, "a planted time in the future counts as just planted")
	farm.from_dict({"plots": {"garden_plot_3": {"crop": "moon_lily", "planted": 0}}})
	_check(farm.is_empty(&"garden_plot_3"), "unknown crops in a save are dropped")


func _test_gathering_near_spawn() -> void:
	print("[Chop and mine near the spawn point]")
	var spawn := Vector3(-15, 0, -5.6)
	var tree := level.get_node("ToolSites/OfficeTree") as HarvestNode
	var rock := level.get_node("ToolSites/OfficeRock") as HarvestNode
	_check(tree.required_tool == ItemDefinition.ToolType.WOOD_AXE and tree.global_position.distance_to(spawn) < 15.0, "a woodcutting tree beside the post office")
	_check(rock.required_tool == ItemDefinition.ToolType.PICKAXE and rock.global_position.distance_to(spawn) < 15.0, "an ore rock beside the post office")
	_check(tree.respawn_max_seconds > tree.respawn_min_seconds and rock.respawn_min_seconds > 0.0, "both grow back after use, after a random time")
