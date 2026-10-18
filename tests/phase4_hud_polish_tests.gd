extends SceneTree
## Actual village, real cargo and live controls. Optional --capture requires a renderer.
var failures := 0
var checks := 0
var capture := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	else:
		print("PASS ", message)

func settle() -> void:
	for i in 40:
		await process_frame

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var village := scene.instantiate()
	root.add_child(village)
	current_scene = village
	await settle()
	var hud := village.get_node("GameplayHUD") as GameplayHUD
	var player := village.get_node("Player") as PlayerController
	var rig := village.get_node("IsoCameraRig") as IsoCameraRig
	var manager := QuestManager.find(self)
	var carrier := PackageCarrier.find_on(player)
	var integration := village.get_node("Phase4DeliveryIntegration") as Phase4DeliveryIntegration
	var presentation: Node = integration.get_visual_layer()
	var combat: Control = presentation.get_node("CombatVisualLayer/CombatHUD").panel
	var minimap: Node = hud.get_node("Minimap")
	var sample := village.get_node("PostOffice/Phase3Showcase") as Phase3Showcase
	check(integration.player == player, "F5 integration uses the real player")
	check(manager.quest_state_changed.is_connected(integration._on_quest_state_changed), "preassigned player does not skip quest signal wiring")
	check(minimap.model.get_player_world().is_equal_approx(player.global_position), "minimap binds the village player")
	check(hud.package_status_hud.get_bound_package() == null, "exhibit never claims to be carried cargo")
	for resolution in [Vector2i(1600,900), Vector2i(1366,768), Vector2i(1280,720)]:
		root.size = resolution
		root.content_scale_size = resolution
		await settle()
		check(hud.wallet_display.get_global_rect().end.y < minimap.compact.get_global_rect().position.y, "wallet above map at %s" % resolution)
		var prompt: Control = village.get_node("InteractionPrompt").panel
		check(not prompt.get_global_rect().intersects(combat.get_global_rect()), "long exhibit prompt clears combat at %s" % resolution)
		await snapshot("spawn", resolution)
	check(manager.accept_quest(&"q002_dragon_egg") == QuestManager.AcceptResult.OK, "accept actual Dragon Egg delivery")
	village.get_node("PostOffice/Markers/ParcelPickupSpot/DragonEggPickup").interactable.interact(player)
	await settle()
	check(carrier.is_carrying(), "real quest pickup gives cargo")
	check(hud.quest_tracker.visible and hud.quest_tracker.title_label.text == manager.get_definition(&"q002_dragon_egg").title, "shared tracker displays actual active quest")
	check(not presentation.get_node("DeliveryHUD").tracker_panel.visible, "duplicate Phase 4 tracker suppressed")
	sample.interactable.interact(player)
	check(hud.package_status_hud.get_bound_package() == carrier.get_package(), "exhibit switch cannot hijack carried package HUD")
	var old_position: Vector3 = minimap.model.get_player_world()
	player.teleport_to(Vector3(14, 0, -26))
	rig.snap_to_target()
	integration.simulate_enemies = false
	await settle()
	check(not minimap.model.get_player_world().is_equal_approx(old_position), "moving real player updates map X/Z")
	check(integration.get_live_enemy_count() == 2, "forest instantiates Slime and Wisp")
	check(minimap.model.count(&"enemy") == 2, "forest enemies appear in minimap model")
	for resolution in [Vector2i(1600,900), Vector2i(1366,768), Vector2i(1280,720)]:
		root.size = resolution
		root.content_scale_size = resolution
		carrier.get_package().set_temperature(98)
		await settle()
		hud.quest_notification.push_message("Hostiles in the Whisperwood! Space: Magic Bolt, Shift: Dash, Q: Package Shield")
		hud.quest_notification.label.text = "Hostiles in the Whisperwood! Space: Magic Bolt, Shift: Dash, Q: Package Shield"
		await settle()
		var panels: Array[Control] = [hud.quest_tracker, hud.wallet_display, minimap.compact, combat, hud.package_indicator, hud.package_status_hud]
		panels.append(village.get_node("QuestJournal").hint_label)
		panels.append(hud.quest_notification.panel)
		panels.append(presentation.get_node("DeliveryHUD").banner_panel)
		var viewport := Rect2(Vector2.ZERO, Vector2(resolution))
		for i in panels.size():
			check(viewport.encloses(panels[i].get_global_rect()), "%s fits %s" % [panels[i].name, resolution])
			for j in range(i + 1, panels.size()):
				check(not panels[i].get_global_rect().intersects(panels[j].get_global_rect()), "%s / %s disjoint at %s" % [panels[i].name, panels[j].name, resolution])
		await snapshot("forest_cargo", resolution)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_M
		key.pressed = true
		minimap._unhandled_input(key)
		await settle()
		check(minimap.expanded.visible, "M expands map at %s" % resolution)
		check(viewport.encloses(minimap.expanded.get_global_rect()), "expanded map fits %s" % resolution)
		await snapshot("expanded", resolution)
		minimap._unhandled_input(key)
		check(not minimap.expanded.visible, "M closes map")
	carrier.get_package().set_temperature(50)
	player.teleport_to(Vector3(14, 0, -31.2))
	await settle()
	check(integration.get_route_target() == village.get_node("NPCs/MageElowen"), "clearing updates live objective to Elowen")
	check(minimap.model.get_marker_world(&"objective").is_equal_approx(village.get_node("NPCs/MageElowen").global_position), "map objective follows delivery progression")
	village.get_node("NPCs/MageElowen").interactable.interact(player)
	await settle()
	check(manager.get_status(&"q002_dragon_egg") == QuestState.Status.REWARDED, "delivery rewards actual Dragon Egg quest")
	check(CourierWallet.find(self).gold > 0, "delivery pays actual wallet")
	check(not hud.package_indicator.visible and not hud.package_status_hud.visible, "delivered cargo clears both package panels")
	check(not minimap.model.has_marker(&"objective"), "completed objective removed from map")
	check(integration.get_live_enemy_count() == 0, "delivery clears forest encounter")
	# Exercise the same occlusion branch used in F5 without changing camera angles.
	var fader := village.get_node("OccluderFader") as OccluderFader
	var wall := village.get_node("PostOffice/Building/WallEastA") as MeshInstance3D
	player.set_physics_process(false)
	var wall_center := wall.global_transform * wall.get_aabb().get_center()
	player.teleport_to(wall_center - rig.camera.global_basis.z * 2.0 - Vector3.UP * 0.4)
	await physics_frame
	await process_frame
	fader._process(1.0)
	check(wall.transparency > 0.0, "intervening post office wall fades")
	print("HUD polish tests: %d passed, %d failed" % [checks - failures, failures])
	village.queue_free()
	await process_frame
	quit(failures)

func snapshot(state: String, resolution: Vector2i) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var directory := "res://docs/validation/hud-polish"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "%s/%s_%dx%d.png" % [directory, state, resolution.x, resolution.y]
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, "rendered " + path)
