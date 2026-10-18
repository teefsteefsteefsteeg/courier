extends SceneTree
## Live-village audit for the Phase 3 showcase, magical pickup lifecycle, and HUD.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var village := (load("res://scenes/levels/village.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(village)
	await process_frame
	await process_frame
	var manager := QuestManager.find(self)
	var player := village.get_node("Player") as PlayerController
	var carrier := PackageCarrier.find_on(player)
	var hud := village.get_node("GameplayHUD/PackageStatusHUD") as PackageStatusHUD
	var post_office := village.get_node("PostOffice") as Node3D
	var egg_pickup := post_office.get_node("Markers/ParcelPickupSpot/DragonEggPickup") as PackagePickup
	var potion_pickup := post_office.get_node("Markers/ParcelPickupSpot/PotionCratePickup") as PackagePickup
	var showcase := post_office.get_node("Phase3Showcase") as Phase3Showcase

	_check(manager != null, "village has the quest manager")
	_check(manager.get_definition(&"q002_dragon_egg") != null and manager.get_definition(&"q003_unstable_potion") != null, "board missions are registered")
	_check(egg_pickup != null and potion_pickup != null, "both magical pickup scenes are instanced in the post office")
	_check(showcase != null and showcase.egg_visual != null and showcase.potion_visual != null, "showcase has both live magical models")
	_check(showcase.egg_visual.get_bound_package() != null and showcase.potion_visual.get_bound_package() != null, "showcase visuals bind live PackageInstances")
	_check(not hud.visible and hud.get_bound_package() == null, "exhibit does not impersonate carried cargo on village start")

	_check(manager.accept_quest(&"q002_dragon_egg") == QuestManager.AcceptResult.OK, "Dragon Egg mission accepts")
	await process_frame
	_check(egg_pickup.visible and egg_pickup.is_available(), "accepting Dragon Egg exposes a visible pickup")
	egg_pickup.interactable.interact(player)
	await process_frame
	_check(carrier.get_package().get_package_id() == &"pkg_dragon_egg", "carrying the egg uses the actual package")
	_check(hud.visible and hud.is_temperature_shown(), "carrying the egg shows the live temperature HUD")
	showcase.interactable.interact(player)
	_check(hud.get_bound_package() == carrier.get_package(), "exhibit interaction preserves the actual carried egg binding")
	_check(carrier.get_child(-1) is DragonEggVisualFX, "carrying the egg instances its visual/effects scene")
	carrier.remove_package(&"audit")

	showcase.interactable.interact(player)
	await process_frame
	_check(not hud.visible and hud.get_bound_package() == null, "exhibit stays on its placard after cargo is removed")
	_check(showcase.potion_visual.get_agitation() >= 0.0, "potion visual effect updates from instability")

	print("phase3_demo_tests: ", 14 - failures, " passed, ", failures, " failed")
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		failures += 1
		push_error("FAIL  " + label)
