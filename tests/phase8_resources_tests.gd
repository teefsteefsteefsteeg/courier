extends SceneTree
## Phase 8 milestone 2: natural resource respawn and tools in every map.
## - A depleted node changes its look, says "regrowing" (never a countdown), draws a random
##   hidden respawn time between its min and max, regrows exactly then, and never pays twice.
## - Runewood Highlands has marked trees, ore rocks, soft soil and fishable river water
##   (RiverWater + a bank FishingSpot), placed on its terrain by GroundSnap.
## - The same axe, pickaxe, shovel and rod work there through the real interact key; the
##   hidden village's trees and pond never count; depletion is per target_id and survives
##   region changes and save/load.
##   godot --headless --path . --script res://tests/phase8_resources_tests.gd

const VILLAGE := "res://scenes/levels/village.tscn"

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var inventory: CourierInventory
var service: GatheringService
var user: ToolUser
var router: Node
var feedback: Array[String] = []
var _now := 2000000.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	level = (load(VILLAGE) as PackedScene).instantiate()
	(level.get_node("GameplayServices/SaveGame") as SaveGame).path = "user://phase8_resources_tests.json"
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	inventory = CourierInventory.find(self)
	service = GatheringService.find(self)
	service.clock = func() -> float: return _now
	user = ToolUser.find_on(player)
	user.feedback.connect(func(text: String, _kind: StringName) -> void: feedback.append(text))
	router = get_first_node_in_group(&"phase6_router")
	await _frames(20)
	for id in [&"woodcutter_axe", &"miner_pickaxe", &"garden_shovel", &"fishing_rod"]:
		inventory.add_item(inventory.get_definition(id))

	await _test_village_respawn()
	await _test_runewood_sites()
	await _test_tools_in_runewood()
	await _test_state_across_regions()

	print("\n=== Phase 8 resources tests: %d passed, %d failed ===" % [_passes, _failures])
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
	Input.flush_buffered_events()
	await physics_frame
	event = event.duplicate() as InputEventAction
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await physics_frame


func _finish(max_frames: int = 900) -> int:
	var frames := 0
	while user.is_busy() and frames < max_frames:
		await physics_frame
		frames += 1
	return frames


## Stands beside a target, facing it, and waits for the interaction focus.
func _stand_at(target: ToolTarget, offset := Vector3(0.6, 0, 0.6)) -> void:
	player.teleport_to(target.get_reach_point() + offset + Vector3.UP * 0.3)
	for i in 30:
		await physics_frame
		if player.is_on_floor() and player.interaction.focused == target.interactable:
			break


func _travel(region: StringName, spawn: StringName = &"Arrival") -> void:
	router.call(&"travel", region, spawn, player)
	for i in 120:
		await physics_frame
		if router.get(&"region_id") == region and not router.get(&"crossing"):
			break
	await _frames(5)


func _sites() -> GroundSnap:
	var active := router.get(&"active_level") as Node
	var found := active.find_children("RunewoodToolSites", "", false, false) if active != null else []
	return found[0] as GroundSnap if not found.is_empty() else null


# --- tests -------------------------------------------------------------------

func _test_village_respawn() -> void:
	print("[Village: hidden, random respawn]")
	var rock := level.get_node("ToolSites/QuarryRock2") as HarvestNode
	inventory.equip(&"miner_pickaxe")
	await _stand_at(rock, Vector3(1.1, 0, 0.9))
	var stone := inventory.get_material_count(&"stone")
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"stone") > stone and not rock.is_available(), "mining the rock pays stone and uses it up")
	_check(rock.depleted_visual.visible and not rock.standing_visual.visible, "the rock is replaced by rubble")
	var prompt := rock.get_interaction_prompt(player)
	var digits := RegEx.create_from_string("[0-9]")
	_check(digits.search(prompt) == null, "no countdown in the prompt (%s)" % prompt)
	var left := service.seconds_until_respawn(rock.target_id)
	_check(left >= rock.respawn_min_seconds and left <= rock.respawn_max_seconds, "a hidden respawn time of %.0f s, within %.0f-%.0f s" % [left, rock.respawn_min_seconds, rock.respawn_max_seconds])
	# The HUD shows no timer either.
	var hud_text := ""
	for label in level.get_node("GameplayHUD").find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			hud_text += (label as Label).text + "\n"
	_check(not hud_text.contains("back in") and not RegEx.create_from_string("[0-9]+:[0-9]{2}").search(hud_text), "no countdown anywhere on the HUD")
	stone = inventory.get_material_count(&"stone")
	feedback.clear()
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"stone") == stone, "a depleted rock pays nothing (no duplicate reward)")
	_now += left + 1.0
	await _frames(70)
	_check(rock.is_available() and rock.standing_visual.visible, "it regrows once its hidden time is up")
	var times := {}
	for i in 16:
		times[roundi(rock.roll_respawn_seconds())] = true
	_check(times.size() >= 6, "respawn times are random (%d different in 16)" % times.size())


func _test_runewood_sites() -> void:
	print("[Runewood tool sites]")
	await _travel(&"runewood")
	_check(router.get(&"region_id") == &"runewood", "the courier is in Runewood")
	var sites := _sites()
	_check(sites != null, "Runewood has its tool sites")
	if sites == null:
		return
	if not sites.is_snapped:
		await sites.snapped
	var ids := {}
	var kinds := {}
	for node in sites.get_children():
		if node is ToolTarget:
			ids[(node as ToolTarget).target_id] = true
			kinds[(node as ToolTarget).required_tool] = true
	_check(ids.size() == 6, "six unique target ids (%s)" % [ids.keys()])
	_check(kinds.has(ItemDefinition.ToolType.WOOD_AXE) and kinds.has(ItemDefinition.ToolType.PICKAXE) and kinds.has(ItemDefinition.ToolType.SHOVEL) and kinds.has(ItemDefinition.ToolType.FISHING_ROD), "trees, ore, soil and a fishing spot")
	var space := player.get_world_3d().direct_space_state
	var grounded := true
	for name in ["RunewoodTree1", "RunewoodTree2", "RunewoodRock1", "RunewoodRock2", "RunewoodSoil1", "MoonbrookBank"]:
		var node := sites.get_node(name) as Node3D
		var at := node.global_position
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.6, 1)
		query.exclude = sites._own_bodies(node)
		if space.intersect_ray(query).is_empty():
			grounded = false
			printerr("    not on the ground: %s at %s" % [name, at])
	_check(grounded, "every site sits on the Runewood terrain")


func _test_tools_in_runewood() -> void:
	print("[Tools in Runewood]")
	var sites := _sites()
	if sites == null:
		return
	var tree := sites.get_node("RunewoodTree1") as HarvestNode
	inventory.equip(&"woodcutter_axe")
	await _stand_at(tree)
	_check(user.find_target(ItemDefinition.ToolType.WOOD_AXE) == tree, "the axe finds the Runewood tree, not a hidden village one")
	var wood := inventory.get_material_count(&"wood")
	await _press(&"interact")
	_check(user.state == ToolUser.State.WORKING and user.target == tree, "E starts chopping in Runewood")
	await _finish()
	_check(inventory.get_material_count(&"wood") > wood and not tree.is_available() and tree.depleted_visual.visible, "the tree pays wood and becomes a stump")
	_check(tree.get_interaction_prompt(player) == "Tree Stump · regrowing", "its prompt has no countdown")
	var rock := sites.get_node("RunewoodRock1") as HarvestNode
	inventory.equip(&"miner_pickaxe")
	await _stand_at(rock, Vector3(1.1, 0, 0.9))
	var stone := inventory.get_material_count(&"stone")
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"stone") > stone and not rock.is_available(), "the pickaxe mines a Runewood rock")
	var soil := sites.get_node("RunewoodSoil1") as HarvestNode
	inventory.equip(&"garden_shovel")
	await _stand_at(soil)
	var clay := inventory.get_material_count(&"clay")
	await _press(&"interact")
	await _finish()
	_check(inventory.get_material_count(&"clay") > clay, "the shovel digs clay in Runewood")
	# Fishing: the river is water, the hidden village pond is not.
	var river := sites.get_node("FixedMoonbrook") as RiverWater
	var spot := sites.get_node("MoonbrookBank") as FishingSpot
	_check(user.find_water(spot.get_work_point()) == river, "the spot's cast point is over the Moonbrook")
	var village_pond := level.get_node("ToolSites/WillowmerePond/Pond") as Pond
	_check(user.find_water(village_pond.global_position) == null, "the hidden village pond does not count in Runewood")
	_check(user.find_water(Vector3(-14, 1, 12)) == null, "dry land on the bank is not water")
	inventory.equip(&"fishing_rod")
	await _stand_at(spot, Vector3(0, 0, 0.4))
	await _press(&"interact")
	_check(user.state == ToolUser.State.FISHING and user.fishing_pond == river, "E at the Moonbrook bank casts into the river")
	_check(river.is_open_water(user.cast_point, 0.0), "the bobber lands in the river (%s)" % user.cast_point)
	user.cancel()
	await _frames(3)


func _test_state_across_regions() -> void:
	print("[Depletion across regions and saves]")
	var sites := _sites()
	if sites == null:
		return
	var tree_id := (sites.get_node("RunewoodTree1") as HarvestNode).target_id
	_check(service.is_depleted(tree_id), "the Runewood tree is depleted")
	await _travel(&"village")
	_check(router.get(&"region_id") == &"village" and service.is_depleted(tree_id), "going home keeps the Runewood stump depleted")
	var village_tree := level.get_node("ToolSites/GroveTree3") as HarvestNode
	_check(village_tree.is_available() and village_tree.is_visible_in_tree(), "village trees are back in view and untouched")
	var saved := service.to_dict()
	service.from_dict({})
	service.from_dict(saved)
	_check(service.is_depleted(tree_id), "a save/load keeps it depleted")
	await _travel(&"runewood")
	var tree := _sites().get_node("RunewoodTree1") as HarvestNode
	_check(not tree.is_available() and tree.depleted_visual.visible, "back in Runewood it is still a stump")
	_now += tree.respawn_max_seconds + 1.0
	await _frames(70)
	_check(tree.is_available() and tree.standing_visual.visible, "and it regrows on its own timer")
	await _travel(&"village")
