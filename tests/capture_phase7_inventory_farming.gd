extends SceneTree
## Renders Phase 7 Milestone B in the real village (GPU window, NOT --headless): the
## inventory's two views with enhanced items, the Toolwright's seed counter, the courier's
## garden at every growth stage and after a harvest. SaveGame is removed so the real save
## is never touched.
##   godot --path . --resolution 1600x900 --script res://tests/capture_phase7_inventory_farming.gd -- <output_dir>

var level: Node3D
var player: PlayerController
var rig: IsoCameraRig
var out_dir: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("screenshots/phase7")
	DirAccess.make_dir_recursive_absolute(out_dir)
	level = (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	for node in level.find_children("*", "SaveGame", true, false):
		node.get_parent().remove_child(node)
		node.free()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	rig = level.get_node("IsoCameraRig")
	await _wait(30)
	var inventory := CourierInventory.find(self)
	var wallet := CourierWallet.find(self)
	wallet.add_gold(200)
	for id in [&"iron_sword", &"magic_staff", &"battle_axe", &"wooden_shield", &"woodcutter_axe", &"miner_pickaxe", &"garden_shovel"]:
		inventory.add_item(inventory.get_definition(id))
	inventory.equip(&"magic_staff")
	inventory.set_enhancement(&"magic_staff", 5)
	inventory.set_enhancement(&"iron_sword", 3)
	inventory.set_enhancement(&"battle_axe", 2)
	inventory.set_enhancement(&"wooden_shield", 1)
	for id in [&"wood", &"stone", &"iron_ore", &"pond_perch"]:
		inventory.add_material(inventory.get_material_definition(id), 6)

	var equipment := level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	await _goto(Vector3(-13, 0, 4.5), 14.0)
	equipment.open()
	await _wait(6)
	await _shot("16_inventory_weapons_and_gear")

	# The Toolwright's seed counter.
	equipment.close()
	await _wait(4)
	var stall := level.get_node("ToolSites/ToolStall") as ToolStall
	await _goto(stall.get_shop_front().global_position, 12.0)
	var shop := level.find_children("*", "ShopUI", true, false)[0] as ShopUI
	shop.open(stall.merchant.get_node("ShopMerchant") as Merchant, player)
	await _wait(4)
	shop.buy_goods(&"wheat_seeds", 5)
	shop.buy_goods(&"carrot_seeds", 5)
	shop.buy_goods(&"pumpkin_seeds", 5)
	# Scroll to the seeds.
	var goods := shop.goods_rows[&"wheat_seeds"]["row"] as Control
	var scroll := goods.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(goods)
	await _wait(6)
	await _shot("17_toolwright_seeds")
	shop.close()
	await _wait(4)

	equipment.open()
	equipment.set_view(EquipmentUI.View.TOOLS)
	equipment.select_item(&"garden_shovel")
	await _wait(6)
	await _shot("18_inventory_tools_and_goods")
	equipment.close()
	await _wait(4)

	# The garden: one bed per stage, then the harvest.
	var farm := FarmService.find(self)
	var crops := [&"wheat", &"carrot", &"pumpkin", &"wheat"]
	for index in 4:
		farm.plant(StringName("garden_plot_%d" % (index + 1)), crops[index], inventory)
	# Advance so the beds show stage 3 (ripe), 2, 1 and 0.
	farm.from_dict({"play_time": 400.0, "plots": {
		"garden_plot_1": {"crop": "wheat", "planted": 400.0 - 125.0},
		"garden_plot_2": {"crop": "carrot", "planted": 400.0 - 125.0},
		"garden_plot_3": {"crop": "pumpkin", "planted": 400.0 - 95.0},
		"garden_plot_4": {"crop": "wheat", "planted": 400.0 - 5.0}}})
	await _goto(Vector3(-13, 0, 6.6), 9.0)
	await _seconds(0.6)
	await _shot("19_garden_growth_stages")
	var ripe := level.get_node("ToolSites/CourierGarden/Plot1") as FarmPlot
	await _goto(ripe.global_position + Vector3(0, 0, -1.6), 9.0)
	await _wait(10)
	await _shot("20_garden_ripe_prompt")
	ripe.interactable.interact(player)
	await _seconds(0.5)
	await _shot("21_garden_harvested")
	var tree := level.get_node("ToolSites/OfficeTree") as Node3D
	await _goto(tree.global_position + Vector3(1.4, 0, 1.4), 11.0)
	await _seconds(0.4)
	await _shot("22_chop_tree_by_post_office")
	quit()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _goto(at: Vector3, zoom: float) -> void:
	player.teleport_to(at)
	rig.zoom_size = zoom
	rig.snap_to_target()
	await _wait(30)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
