extends "res://tests/capture_phase5h_screenshots.gd"
## Render the actual playable generated rod and material UI, using the isolated
## inherited save and the real keyboard-driven fishing walkthrough.


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if not args.is_empty() else OS.get_user_data_dir().path_join("screenshots/phase6")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_delete_save()
	await _load_level()
	await _shop()
	await _fishing_bank()
	rig.set_zoom(6.0)
	rig.snap_to_target()
	await _wait(20)
	await _shot("17_generated_rod_closeup")
	for id in [&"pond_perch", &"silver_trout", &"golden_carp", &"wood", &"stone", &"iron_ore", &"clay"]:
		inventory.add_material(inventory.get_material_definition(id), 3)
	await _equipment()
	# Show the live selling section and complete a sale through its button.
	var stall := level.get_node("ToolSites/ToolStall") as ToolStall
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	player.teleport_to(stall.get_shop_front().global_position)
	rig.snap_to_target()
	await _wait(10)
	shop.open(stall.merchant.get_node("ShopMerchant") as Merchant, player)
	await _wait(5)
	var scroll := shop.item_list.get_parent() as ScrollContainer
	scroll.scroll_vertical = 100000
	await _wait(5)
	await _shot("18_toolwright_sell_materials")
	var gold := CourierWallet.find(self).gold
	(shop.sell_rows[&"clay"]["button"] as Button).pressed.emit()
	_report(inventory.get_material_count(&"clay") == 0 and CourierWallet.find(self).gold > gold, "rendered shop sells gathered clay")
	shop.close()
	_delete_save()
	print("P6 done, %d problems" % failures)
	quit(failures)
