extends SceneTree
## Phase 5H RPG tool checks in the real village: tool and material data, tools in the
## inventory, quick slots and the hand, the TOOL attack style (tools never attack, weapons
## never work tool targets), every placed ToolTarget, validation (tool, distance, state,
## materials, depletion), chopping, mining, digging, repairing and fishing with results at
## the clip's impact moment, depletion and respawn, cancelling, no duplicate rewards, the
## Toolwright's shop (buying tools, selling materials), the tool HUD and Equipment window,
## and save/load of tools, materials and world state (and old saves without them).
## Run headless from the project root:
##   godot --headless --path . --script res://tests/tool_system_tests.gd
## Exit code = number of failed checks.

const VILLAGE := "res://scenes/levels/village.tscn"
const TOOLS := [&"fishing_rod", &"carpenter_hammer", &"woodcutter_axe", &"miner_pickaxe", &"garden_shovel", &"mason_trowel"]
const MATERIALS := [&"pond_perch", &"silver_trout", &"golden_carp", &"wood", &"stone", &"iron_ore", &"clay"]
## Placed targets: node path under ToolSites -> [target_id, tool type].
const TARGETS := {
	"WillowmerePond/Jetty": [&"pond_jetty", ItemDefinition.ToolType.HAMMER],
	"WillowmerePond/JettySpot": [&"pond_jetty_spot", ItemDefinition.ToolType.FISHING_ROD],
	"WillowmerePond/DigWest": [&"pond_dig_west", ItemDefinition.ToolType.SHOVEL],
	"WillowmerePond/DigNorth": [&"pond_dig_north", ItemDefinition.ToolType.SHOVEL],
	"GroveTree1": [&"grove_tree_1", ItemDefinition.ToolType.WOOD_AXE],
	"GroveTree2": [&"grove_tree_2", ItemDefinition.ToolType.WOOD_AXE],
	"GroveTree3": [&"grove_tree_3", ItemDefinition.ToolType.WOOD_AXE],
	"QuarryRock1": [&"quarry_rock_1", ItemDefinition.ToolType.PICKAXE],
	"QuarryRock2": [&"quarry_rock_2", ItemDefinition.ToolType.PICKAXE],
	"QuarryRock3": [&"quarry_rock_3", ItemDefinition.ToolType.PICKAXE],
	"QuarryWall": [&"quarry_wall", ItemDefinition.ToolType.TROWEL],
	"PumpkinFence": [&"pumpkin_fence", ItemDefinition.ToolType.HAMMER],
}

var _failures: int = 0
var _passes: int = 0
var level: Node3D
var player: PlayerController
var user: ToolUser
var combat: CombatController
var character: KayKitCharacter
var inventory: CourierInventory
var wallet: CourierWallet
var service: GatheringService
var feedback: Array[String] = []
var _now := 1000000.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _load_level()
	_test_data()
	_test_inventory()
	await _test_equipment_and_combat()
	_test_targets()
	await _test_validation()
	await _test_chop()
	await _test_mine_and_dig()
	await _test_cancel()
	await _test_repair()
	await _test_fishing()
	await _test_weapons_leave_targets_alone()
	await _test_shop()
	await _test_ui()
	await _test_save_load()

	print("\n=== Tool system tests: %d passed, %d failed ===" % [_passes, _failures])
	quit(_failures)


func _load_level() -> void:
	if level != null:
		root.remove_child(level)
		level.free()
	level = (load(VILLAGE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.get_node("Player")
	user = ToolUser.find_on(player)
	combat = player.get_node("Combat") as CombatController
	character = player.find_children("*", "KayKitCharacter", true, false)[0] as KayKitCharacter
	inventory = CourierInventory.find(self)
	wallet = CourierWallet.find(self)
	service = GatheringService.find(self)
	service.clock = func() -> float: return _now
	feedback.clear()
	user.feedback.connect(func(text: String, _kind: StringName) -> void: feedback.append(text))
	user.rng.seed = 11
	for i in 10:
		await physics_frame


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


func _target(path: String) -> ToolTarget:
	return level.get_node("ToolSites/" + path) as ToolTarget


func _give_tool(id: StringName) -> void:
	inventory.add_item(inventory.get_definition(id))
	inventory.equip(id)


func _give(id: StringName, amount: int) -> void:
	inventory.add_material(inventory.get_material_definition(id), amount)


## Puts the courier at a target's interaction point, facing it.
func _stand_at(target: ToolTarget, offset := Vector3(0.5, 0, 0.5)) -> void:
	player.teleport_to(target.get_reach_point() + offset)
	await _frames(4)


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


## Steps until the courier's tool job ends (or max_frames). Returns the frames taken.
func _finish(max_frames: int = 900) -> int:
	var frames := 0
	while user.is_busy() and frames < max_frames:
		await physics_frame
		frames += 1
	return frames


# --- data ------------------------------------------------------------------------------

func _test_data() -> void:
	print("[Data]")
	for id in TOOLS:
		var item := inventory.get_definition(id)
		_check(item != null and item.is_tool() and not item.is_weapon() and item.is_quick_slottable() and item.slot == ItemDefinition.Slot.MAIN_HAND
				and item.held_model != null and item.icon != null and item.price > 0, "%s is a registered main-hand tool with icon and held model" % id)
	var models := TOOLS.map(func(id: StringName) -> String: return inventory.get_definition(id).held_model.resource_path)
	_check(models.filter(func(p: String) -> bool: return p.begins_with("res://assets/models/kaykit_rpg_tools/")).size() == 5 and models.has("res://scenes/props/tools/fishing_rod.tscn"),
			"five tools hold KayKit RPG Tools models; the rod (not in the pack) is built from primitives")
	for id in MATERIALS:
		var material := inventory.get_material_definition(id)
		_check(material != null and material.icon != null and material.sell_price > 0, "%s is a registered material with icon and price" % id)
	var catalog := load("res://data/shops/toolwright.tres") as ShopCatalog
	_check(catalog.items.size() == 6 and catalog.buys_materials and catalog.items.all(func(i: ItemDefinition) -> bool: return i.is_tool()), "the Toolwright sells the six tools and buys materials")
	for id in [&"iron_sword", &"battle_axe", &"hunting_bow", &"magic_staff"]:
		var weapon := inventory.get_definition(id)
		_check(weapon.is_weapon() and not weapon.is_tool(), "%s stays a weapon, not a tool" % id)


func _test_inventory() -> void:
	print("[Materials in the inventory]")
	var wood := inventory.get_material_definition(&"wood")
	var changes: Array = []
	var record := func(m: MaterialItem, count: int, delta: int) -> void: changes.append([m.material_id, count, delta])
	inventory.materials_changed.connect(record)
	_check(inventory.add_material(wood, 5) == 5 and inventory.get_material_count(&"wood") == 5, "adding 5 wood")
	_check(inventory.has_materials({&"wood": 5}) and not inventory.has_materials({&"wood": 6}), "has_materials checks counts")
	_check(not inventory.remove_materials({&"wood": 2, &"stone": 1}) and inventory.get_material_count(&"wood") == 5, "a removal that cannot be paid in full takes nothing")
	_check(inventory.remove_materials({&"wood": 2}) and inventory.get_material_count(&"wood") == 3, "removal takes exactly what was asked")
	_check(inventory.add_material(wood, 5000) == CourierInventory.MAX_STACK - 3 and inventory.get_material_count(&"wood") == CourierInventory.MAX_STACK, "stacks cap at %d" % CourierInventory.MAX_STACK)
	_check(changes.size() == 3 and changes[0] == [&"wood", 5, 5] and changes[1] == [&"wood", 3, -2], "materials_changed reports count and delta")
	inventory.materials_changed.disconnect(record)
	var saved := inventory.to_dict()
	_check((saved["materials"] as Dictionary).get("wood") == CourierInventory.MAX_STACK, "to_dict stores materials")
	inventory.from_dict({"owned": [], "equipped": {}})
	_check(inventory.get_material_counts().is_empty(), "an old save without materials loads with none")
	inventory.from_dict({"owned": [], "materials": {"wood": 4, "unicorn_hair": 3, "clay": -5}})
	_check(inventory.get_material_count(&"wood") == 4 and inventory.get_material_counts().size() == 1, "unknown and negative materials in a save are dropped")
	inventory.from_dict({})


# --- equipment and combat ----------------------------------------------------------------

func _test_equipment_and_combat() -> void:
	print("[Tools in hand never attack]")
	_give_tool(&"woodcutter_axe")
	await _frames(2)
	_check(combat.get_attack_style() == CombatController.AttackStyle.TOOL, "a tool in the main hand sets the TOOL attack style")
	var held := character.get_held_item_node()
	_check(held != null and held.scene_file_path == "res://assets/models/kaykit_rpg_tools/axe.gltf", "the axe model is in the courier's right hand")
	_check(inventory.find_quick_slot(&"woodcutter_axe") == 0, "a bought tool fills the first empty quick slot")
	# Pip is a villager: nothing the axe does may hurt anyone.
	player.teleport_to(Vector3(2.6, 0, 4.0))
	await _frames(4)
	var requested := [0]
	var count_request := func() -> void: requested[0] += 1
	combat.tool_use_requested.connect(count_request)
	var projectiles := level.find_children("*", "CombatProjectile", true, false).size()
	var melee := [0]
	var count_melee := func(_d: Vector3, _h: bool) -> void: melee[0] += 1
	combat.melee_started.connect(count_melee)
	await _press(&"combat_magic_bolt")
	_check(requested[0] == 1 and melee[0] == 0 and level.find_children("*", "CombatProjectile", true, false).size() == projectiles, "Space with a tool asks the ToolUser instead of attacking (no bolt, no swing)")
	_check(not user.is_busy() and feedback.size() > 0 and feedback[-1].begins_with("No marked tree"), "with no tree in reach it says where to go (%s)" % (feedback[-1] if feedback.size() > 0 else ""))
	combat.tool_use_requested.disconnect(count_request)
	combat.melee_started.disconnect(count_melee)
	inventory.add_item(inventory.get_definition(&"iron_sword"))
	inventory.equip(&"iron_sword")
	await _frames(2)
	_check(combat.get_attack_style() == CombatController.AttackStyle.FAST_MELEE and character.get_held_item_node().scene_file_path == inventory.get_definition(&"iron_sword").held_model.resource_path,
			"equipping a sword restores weapon combat and its model")
	inventory.equip(&"woodcutter_axe")
	var bar := level.get_node("GameplayHUD/QuickWeaponBar") as QuickWeaponBar
	inventory.assign_quick_slot(1, &"iron_sword")
	await _frames(1)
	_check(bar.select(1) and inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND).item_id == &"iron_sword" and bar.select(0) and inventory.get_equipped_tool().item_id == &"woodcutter_axe",
			"quick slots switch between a weapon and a tool")
	await _frames(1)
	_check(bar.info_label.text == "Woodcutter's Axe" and bar.stats_label.text.begins_with("Tool"), "the quick bar shows the tool in hand (%s)" % bar.stats_label.text)
	inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	await _frames(1)
	_check(combat.get_attack_style() == CombatController.AttackStyle.MAGIC_BOLT and character.get_held_item_node() == null, "putting the tool away gives back bare-hand bolts")
	_give_tool(&"fishing_rod")
	await _frames(1)
	var rod := character.get_held_item_node()
	_check(rod != null and rod.find_child("Tip") != null and not rod.transform.basis.is_equal_approx(Basis.IDENTITY), "the rod is held raised (its own hand pose) and has a line tip")


func _test_targets() -> void:
	print("[Placed tool targets]")
	var ids := {}
	for path in TARGETS:
		var target := _target(path)
		var spec: Array = TARGETS[path]
		_check(target != null and target.target_id == spec[0] and target.required_tool == spec[1] and target.interactable != null and target.interactable.collision_layer == 8,
				"%s: %s, needs a %s, has an interaction point" % [path, spec[0], ItemDefinition.tool_type_name(spec[1])])
		ids[target.target_id] = true
		# Regression: the jetty spot's reach (1.6 m) was shorter than its prompt's range, so a
		# cast started at the edge of the prompt was cancelled as "left the site" next frame.
		var sphere := (target.interactable.get_node("CollisionShape3D") as CollisionShape3D).shape as SphereShape3D
		var detector := (player.interaction.get_node("CollisionShape3D") as CollisionShape3D).shape as SphereShape3D
		_check(target.reach >= sphere.radius + detector.radius, "%s reach %.1f m covers its prompt's range %.1f m" % [path, target.reach, sphere.radius + detector.radius])
	_check(ids.size() == TARGETS.size() and get_nodes_in_group(ToolTarget.GROUP).size() == TARGETS.size(), "%d tool targets in the village, ids unique" % TARGETS.size())
	var harvest := get_nodes_in_group(ToolTarget.GROUP).filter(func(t: Node) -> bool: return t is HarvestNode)
	var trees := level.find_children("*", "StaticBody3D", true, false).filter(func(b: Node) -> bool: return b.scene_file_path.contains("tree"))
	_check(harvest.size() == 8 and trees.size() > 20, "only 8 designated nodes are harvestable among %d decorative trees" % trees.size())
	_check(level.find_children("*", "Pond", true, false).size() == 1 and get_nodes_in_group(Pond.GROUP).size() == 1, "one pond: the only water")


# --- validation ---------------------------------------------------------------------------

func _test_validation() -> void:
	print("[Validation]")
	var tree := _target("GroveTree3")
	inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	inventory.from_dict({})
	await _stand_at(tree)
	_check(user.get_block_reason(tree).begins_with("You need a Woodcutting axe") and tree.get_interaction_prompt(player).ends_with("needs a Woodcutting axe"), "without the tool: refused, and the prompt says which tool")
	_give_tool(&"miner_pickaxe")
	inventory.add_item(inventory.get_definition(&"woodcutter_axe"))
	_check(user.get_block_reason(tree).begins_with("Equip your Woodcutter's Axe"), "with the wrong tool in hand: told to equip the owned axe")
	inventory.equip(&"woodcutter_axe")
	player.teleport_to(tree.global_position + Vector3(6, 0, 6))
	await _frames(4)
	_check(user.get_block_reason(tree).begins_with("Get closer"), "too far: refused")
	await _stand_at(tree)
	_check(user.get_block_reason(tree) == "" and tree.get_interaction_prompt(player) == "Chop Marked Tree", "in reach with the axe: allowed ('Chop Marked Tree')")
	var carrier := PackageCarrier.find_on(player)
	var package := PackageInstance.new(load("res://data/packages/pkg_ordinary_parcel.tres"))
	carrier.pick_up(package)
	_check(user.get_block_reason(tree).begins_with("Put the package down"), "carrying a package: refused")
	carrier.drop_package()
	for pickup in level.find_children("*", "PackagePickup", true, false):
		if pickup.get_parent() == level:
			pickup.queue_free()
	await _frames(2)
	combat.try_dash(Vector3.RIGHT)
	_check(user.get_block_reason(tree) == "Not while dashing.", "dashing: refused")
	await _frames(20)
	player.input_enabled = false
	_check(not user.begin(tree) and not user.is_busy(), "courier not in control (dialogue, window): refused")
	player.input_enabled = true
	await _stand_at(tree)


func _test_chop() -> void:
	print("[Woodcutting]")
	var tree := _target("GroveTree3") as HarvestNode
	await _stand_at(tree)
	var gained: Array = []
	var on_gain := func(m: MaterialItem, _c: int, d: int) -> void: gained.append([m.material_id, d, user.get_progress().x, user._stroke_time])
	inventory.materials_changed.connect(on_gain)
	var strokes: Array[int] = []
	var on_stroke := func(done: int, _total: int) -> void: strokes.append(done)
	user.action_progress.connect(on_stroke)
	await _press(&"interact")
	_check(user.state == ToolUser.State.WORKING and user.target == tree and not player.input_enabled, "E at a marked tree starts chopping and pauses the courier's input")
	_check(character.one_shot_action == &"tool_chop", "the chop clip plays")
	var frames := await _finish()
	inventory.materials_changed.disconnect(on_gain)
	user.action_progress.disconnect(on_stroke)
	_check(strokes == [0, 1, 2, 3, 4], "four strokes land one by one %s" % [strokes])
	var stroke_length := character.get_action_length(&"tool_chop", tree.stroke_speed)
	_check(gained.size() == 1 and gained[0][0] == &"wood" and gained[0][1] >= 2 and gained[0][1] <= 4, "felling pays 2-4 wood once (%s)" % [gained])
	_check(gained.size() == 1 and absf(gained[0][3] - stroke_length * KayKitCharacter.TOOL_IMPACT[&"tool_chop"]) < 0.05,
			"the wood arrives at the last stroke's impact (%.2f s into a %.2f s swing)" % [gained[0][3] if gained.size() == 1 else -1.0, stroke_length])
	_check(frames > 60 * 3 and frames < 60 * 6 and player.input_enabled, "the job takes %.1f s, then the courier is free" % (frames / 60.0))
	_check(not tree.is_available() and tree.depleted_visual.visible and not tree.standing_visual.visible and not (tree.standing_visual.get_node("Tree") as Node).can_process(),
			"a stump replaces the tree and the trunk no longer blocks")
	var wood := inventory.get_material_count(&"wood")
	feedback.clear()
	await _press(&"interact")
	_check(not user.is_busy() and inventory.get_material_count(&"wood") == wood and feedback.size() > 0 and feedback[-1].contains("back in 4:00"), "a stump can't be chopped again (%s)" % (feedback[-1] if feedback.size() > 0 else ""))
	_check(tree.get_interaction_prompt(player).begins_with("Tree Stump · back in"), "the prompt shows the regrow time (%s)" % tree.get_interaction_prompt(player))
	_now += 239.0
	_check(not tree.is_available(), "still a stump after 239 s")
	_now += 2.0
	await _frames(70)
	_check(tree.is_available() and tree.standing_visual.visible and (tree.standing_visual.get_node("Tree") as Node).can_process(), "after 240 s the tree has grown back")


func _test_mine_and_dig() -> void:
	print("[Mining and digging]")
	_give_tool(&"miner_pickaxe")
	var rock := _target("QuarryRock2") as HarvestNode
	rock.rng.seed = 3
	# Outside the boulder's 0.83 m collider (closer would land the courier on top of it).
	await _stand_at(rock, Vector3(1.1, 0, 0.9))
	var stone := inventory.get_material_count(&"stone")
	await _press(&"interact")
	_check(character.one_shot_action == &"tool_mine", "the pickaxe swings at the ore rock")
	await _finish()
	_check(inventory.get_material_count(&"stone") - stone >= 2 and not rock.is_available() and rock.depleted_visual.visible, "mining pays stone and leaves rubble (%s)" % feedback[-1])
	var ore := 0
	for seed in 20:
		var trial := _target("QuarryRock3") as HarvestNode
		service.from_dict({})
		trial.rng.seed = seed
		var before := inventory.get_material_count(&"iron_ore")
		trial.complete(user)
		ore += inventory.get_material_count(&"iron_ore") - before
	_check(ore >= 5 and ore <= 15, "iron ore turns up about half the time (%d of 20)" % ore)
	_give_tool(&"garden_shovel")
	var dig := _target("WillowmerePond/DigNorth") as HarvestNode
	await _stand_at(dig)
	var clay := inventory.get_material_count(&"clay")
	await _press(&"interact")
	_check(character.one_shot_action == &"tool_dig", "the shovel digs (pick-up clip)")
	await _finish()
	_check(inventory.get_material_count(&"clay") > clay and dig.depleted_visual.visible, "digging pays clay and leaves a hole")


func _test_cancel() -> void:
	print("[Cancelling]")
	_give_tool(&"woodcutter_axe")
	var tree := _target("GroveTree2") as HarvestNode
	await _stand_at(tree)
	var wood := inventory.get_material_count(&"wood")
	await _press(&"interact")
	await _frames(70)
	await _press(&"move_left")
	_check(not user.is_busy() and player.input_enabled and inventory.get_material_count(&"wood") == wood and tree.is_available(), "moving stops the job before the last stroke: no wood, tree still standing")
	await _press(&"interact")
	await _frames(20)
	combat.health.apply_damage(5.0, Vector3.ZERO)
	await _frames(2)
	_check(not user.is_busy() and tree.is_available(), "taking damage interrupts the job")
	combat.health.heal(100.0)


func _test_repair() -> void:
	print("[Repairing]")
	_give_tool(&"carpenter_hammer")
	var jetty := _target("WillowmerePond/Jetty") as RepairSite
	var spot := _target("WillowmerePond/JettySpot") as FishingSpot
	var blocker := jetty.get_node("Blocker") as StaticBody3D
	_check(not spot.is_available() and not spot.interactable.enabled and blocker.can_process(), "the broken jetty is blocked off and its fishing spot closed")
	inventory.remove_materials({&"wood": inventory.get_material_count(&"wood")})
	_give(&"wood", 2)
	await _stand_at(jetty, Vector3(0.3, 0, 0.3))
	_check(jetty.get_interaction_prompt(player).ends_with("needs 4 Wood (you have 2)"), "the prompt lists the missing wood (%s)" % jetty.get_interaction_prompt(player))
	feedback.clear()
	await _press(&"interact")
	_check(not user.is_busy() and feedback.size() > 0 and feedback[-1].contains("needs 4 Wood"), "repair refused without the materials")
	_give(&"wood", 3)
	var gold := wallet.gold
	var reputation := wallet.reputation
	await _press(&"interact")
	_check(user.state == ToolUser.State.WORKING and character.one_shot_action == &"tool_hammer", "with 5 wood the hammering starts")
	await _frames(30)
	_check(inventory.get_material_count(&"wood") == 5 and wallet.gold == gold, "nothing is taken or paid before the last stroke")
	await _finish()
	_check(jetty.is_repaired() and inventory.get_material_count(&"wood") == 1 and wallet.gold == gold + 30 and wallet.reputation == reputation + 5,
			"repaired: 4 wood used, +30 gold, +5 reputation (%s)" % feedback[-1])
	_check(jetty.repaired_visual.visible and not jetty.damaged_visual.visible and not blocker.can_process() and spot.is_available() and spot.interactable.enabled,
			"the jetty is whole, walkable, and its fishing spot open")
	_check(not jetty.interactable.enabled and not service.mark_repaired(&"pond_jetty"), "it cannot be repaired again")
	gold = wallet.gold
	jetty.complete(user)
	_check(wallet.gold == gold, "a second completion pays nothing")
	# Trowel: stone and clay.
	_give_tool(&"mason_trowel")
	var wall := _target("QuarryWall") as RepairSite
	_give(&"stone", 3)
	_give(&"clay", 1)
	await _stand_at(wall, Vector3(0.2, 0, 0.3))
	await _press(&"interact")
	_check(character.one_shot_action == &"tool_trowel", "the trowel works the crumbled wall")
	await _finish()
	_check(wall.is_repaired() and (wall.repaired_visual.get_node("Wall") as Node3D).visible, "the quarry wall is re-set (%s)" % feedback[-1])


func _test_fishing() -> void:
	print("[Fishing]")
	_give_tool(&"fishing_rod")
	user.bite_wait_min = 0.5
	user.bite_wait_max = 0.5
	var pond := level.find_children("*", "Pond", true, false)[0] as Pond
	# Dry land.
	player.teleport_to(pond.global_position + Vector3(-12, 0, 6))
	await _frames(4)
	feedback.clear()
	await _press(&"combat_magic_bolt")
	_check(not user.is_busy() and feedback[-1].begins_with("No open water"), "Space with the rod on dry land does not cast")
	_check(not pond.is_open_water(player.global_position) and pond.is_open_water(pond.global_position) and not pond.is_open_water(pond.global_position + Vector3(0, 0, pond.radius_z * 1.3)), "the pond knows its open water")
	# From the west bank.
	player.teleport_to(pond.global_position + Vector3(-pond.shore_radius(PI) - 0.6, 0, 0))
	player.facing.visual_root.rotation.y = FacingComponent.yaw_for_direction(Vector3.RIGHT)
	await _frames(4)
	_check(pond.is_open_water(user.get_bank_cast_point()), "facing the water from the bank, the cast lands in open water")
	await _press(&"combat_magic_bolt")
	_check(user.state == ToolUser.State.FISHING and user.fish_state == ToolUser.FishState.CASTING and character.one_shot_action == &"tool_cast", "Space casts (the throw clip)")
	while user.fish_state == ToolUser.FishState.CASTING:
		await physics_frame
	_check(user.bobber != null and user.line != null and pond.is_open_water(user.bobber.global_position), "the bobber floats on open water with a line to the rod tip")
	while user.fish_state == ToolUser.FishState.WAITING:
		await physics_frame
	_check(user.fish_state == ToolUser.FishState.BITE, "a fish bites")
	var counts := _fish_count()
	await _press(&"interact")
	_check(user.fish_state == ToolUser.FishState.REELING and character.one_shot_action == &"tool_reel", "E during the bite hooks it and reels in")
	await _finish()
	_check(_fish_count() == counts + 1 and feedback[-1].begins_with("Caught a"), "a fish goes into the inventory (%s)" % feedback[-1])
	_check(user.bobber == null and player.input_enabled, "the line is reeled in and the courier is free")
	# Too early, and too late.
	await _press(&"combat_magic_bolt")
	await _frames(70)
	await _press(&"interact")
	_check(not user.is_busy() and _fish_count() == counts + 1 and feedback[-1].begins_with("Too soon"), "pulling before the bite loses the fish")
	await _press(&"combat_magic_bolt")
	while user.fish_state != ToolUser.FishState.BITE:
		await physics_frame
	await _frames(int(user.bite_window * 60.0) + 5)
	_check(not user.is_busy() and _fish_count() == counts + 1 and feedback[-1] == "It got away...", "missing the bite window loses the fish")
	# The repaired jetty's spot: better odds of a golden carp.
	var spot := _target("WillowmerePond/JettySpot") as FishingSpot
	player.teleport_to(spot.global_position)
	await _frames(4)
	_check(player.interaction.focused == spot.interactable and spot.get_interaction_prompt(player) == "Fish at the Jetty", "on the jetty: '[E] Fish at the Jetty'")
	await _press(&"interact")
	_check(user.state == ToolUser.State.FISHING and user.target == spot and spot.pond.is_open_water(user.cast_point), "E on the jetty casts beyond its end")
	user.cancel()
	var rng := RandomNumberGenerator.new()
	var plain := 0
	var jetty := 0
	for i in 2000:
		rng.seed = i
		plain += 1 if pond.pick_fish(rng, 1.0).material_id == &"golden_carp" else 0
		rng.seed = i
		jetty += 1 if pond.pick_fish(rng, spot.catch_bonus).material_id == &"golden_carp" else 0
	_check(plain > 100 and plain < 220 and jetty > plain * 2, "golden carp: %d of 2000 from the bank, %d with the jetty bonus" % [plain, jetty])


func _fish_count() -> int:
	return inventory.get_material_count(&"pond_perch") + inventory.get_material_count(&"silver_trout") + inventory.get_material_count(&"golden_carp")


func _test_weapons_leave_targets_alone() -> void:
	print("[Weapons never work tool targets]")
	var tree := _target("GroveTree1") as HarvestNode
	await _stand_at(tree)
	for weapon in [&"iron_sword", &"magic_staff"]:
		inventory.add_item(inventory.get_definition(weapon))
		inventory.equip(weapon)
		await _frames(2)
		var wood := inventory.get_material_count(&"wood")
		await _press(&"combat_magic_bolt")
		await _frames(40)
		_check(not user.is_busy() and tree.is_available() and inventory.get_material_count(&"wood") == wood, "attacking a marked tree with the %s does not chop it" % weapon)
		await _press(&"interact")
		_check(not user.is_busy() and feedback[-1].begins_with("Equip your Woodcutter's Axe"), "E with the %s asks for the axe" % weapon)


# --- shop and UI -------------------------------------------------------------------------

func _test_shop() -> void:
	print("[Toolwright]")
	inventory.unequip(ItemDefinition.Slot.MAIN_HAND)
	var stall := level.find_children("*", "ToolStall", true, false)[0] as ToolStall
	player.teleport_to(stall.get_shop_front().global_position)
	await _frames(5)
	_check(player.interaction.focused == stall.merchant.interactable, "Toolwright Hobb is in reach from the shop front")
	await process_frame
	await process_frame
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	_check(prompt.label.text.ends_with("Browse wares of Toolwright Hobb"), "prompt: %s" % prompt.label.text)
	await _press(&"interact")
	var shop := level.get_node("GameplayHUD/ShopUI") as ShopUI
	_check(shop.is_open() and shop.rows.size() == 6, "talking to Hobb opens his shop with the six tools")
	_check(shop.sell_rows.size() == 7, "and a sell section for the seven materials")
	inventory.remove_materials(inventory.get_material_counts())
	_give(&"silver_trout", 3)
	_give(&"iron_ore", 2)
	shop._refresh_rows()
	_check((shop.sell_rows[&"silver_trout"]["row"] as Control).visible and not (shop.sell_rows[&"wood"]["row"] as Control).visible, "only carried materials are offered")
	var gold := wallet.gold
	(shop.sell_rows[&"silver_trout"]["button"] as Button).pressed.emit()
	_check(wallet.gold == gold + 27 and inventory.get_material_count(&"silver_trout") == 0, "selling 3 Silver Trout pays 27 gold")
	_check(shop.sell_all(&"wood") == 0 and wallet.gold == gold + 27, "selling what you don't carry pays nothing")
	shop.close()
	await _frames(3)
	var armory_shop_open := false
	var armory := level.get_node("Armory") as Armory
	player.teleport_to(armory.get_shop_front().global_position)
	await _frames(5)
	await _press(&"interact")
	armory_shop_open = shop.is_open() and shop.sell_rows.is_empty()
	_check(armory_shop_open, "Brenna's Armory still opens, and buys nothing")
	_check(shop.sell_all(&"iron_ore") == 0 and inventory.get_material_count(&"iron_ore") == 2, "the Armory will not buy ore")
	shop.close()
	await _frames(3)


func _test_ui() -> void:
	print("[Tool HUD and Equipment window]")
	var hud := level.get_node("GameplayHUD/ToolActionHUD") as ToolActionHUD
	_give_tool(&"woodcutter_axe")
	_now += 1000.0
	var tree := _target("GroveTree1") as HarvestNode
	await _stand_at(tree)
	await process_frame
	_check(not hud.visible, "the tool HUD is hidden while idle")
	await _press(&"interact")
	await _frames(70)
	await process_frame
	await process_frame
	var prompt := level.get_node("InteractionPrompt") as InteractionPrompt
	_check(hud.visible and hud.title_label.text == "Chopping · Marked Tree" and hud.status_label.text == "Stroke 2 of 4" and hud.bar.value == 1, "while chopping: '%s', '%s'" % [hud.title_label.text, hud.status_label.text])
	_check(not prompt.panel.visible, "the interaction prompt steps aside while working")
	await _finish()
	await process_frame
	await process_frame
	_check(not hud.visible and prompt.panel.visible, "afterwards the HUD hides and the prompt returns")
	await _press(&"toggle_equipment")
	var equipment := level.get_node("GameplayHUD/EquipmentUI") as EquipmentUI
	await _frames(2)
	var headers := equipment.item_list.get_children().filter(func(c: Node) -> bool: return c is Label).map(func(l: Label) -> String: return l.text)
	_check(equipment.is_open() and headers == ["Weapons", "Tools", "Off-hand", "Materials"], "the Equipment window has Weapons, Tools, Off-hand and Materials sections %s" % [headers])
	_check(equipment.rows.has(&"garden_shovel") and (equipment.rows[&"woodcutter_axe"]["slots"] as Array).size() == 5, "tools can be equipped and quick-slotted there")
	var wood_label := equipment.material_rows[&"wood"]["label"] as Label
	_check(wood_label.text == "Wood × %d" % inventory.get_material_count(&"wood"), "materials show their counts (%s)" % wood_label.text)
	await _press(&"toggle_equipment")


func _test_save_load() -> void:
	print("[Save and load]")
	_give_tool(&"garden_shovel")
	var save := SaveGame.find(self)
	var data := save.to_dict()
	var gathering: Dictionary = data["gathering"]
	_check((gathering["repaired"] as Array).has("pond_jetty") and (gathering["repaired"] as Array).has("quarry_wall"), "the save lists repaired structures")
	_check((gathering["depleted"] as Dictionary).has("grove_tree_1") and (gathering["counts"] as Dictionary).get("fish", 0) == 1 and (gathering["counts"] as Dictionary).get("repair", 0) == 2,
			"the save lists depleted nodes and tallies (%s)" % [gathering["counts"]])
	_check((data["inventory"]["materials"] as Dictionary).size() > 0 and (data["inventory"]["owned"] as Array).has("garden_shovel") and data["inventory"]["equipped"]["MAIN_HAND"] == "garden_shovel",
			"the save lists tools, the tool in hand and materials")
	var json := JSON.stringify(data)
	var clock := _now
	await _load_level()
	_now = clock
	var fresh_jetty := _target("WillowmerePond/Jetty") as RepairSite
	_check(not fresh_jetty.is_repaired() and inventory.get_owned_ids().is_empty(), "a new village starts with nothing repaired and no tools")
	save = SaveGame.find(self)
	save.from_dict(JSON.parse_string(json))
	await _frames(3)
	_check(fresh_jetty.is_repaired() and fresh_jetty.repaired_visual.visible and _target("WillowmerePond/JettySpot").interactable.enabled, "loading restores the repaired jetty and its fishing spot")
	_check(not (_target("GroveTree1") as HarvestNode).is_available() and (_target("GroveTree1") as HarvestNode).depleted_visual.visible, "and the felled tree")
	_check(inventory.get_equipped_tool() != null and inventory.get_equipped_tool().item_id == &"garden_shovel" and character.get_held_item_node().scene_file_path.ends_with("shovel.gltf"), "and the shovel in hand")
	var saved_inventory: Dictionary = JSON.parse_string(json)["inventory"]
	var saved_materials: Dictionary = saved_inventory["materials"]
	var materials_match := inventory.get_material_counts().size() == saved_materials.size()
	for id in saved_materials:
		materials_match = materials_match and inventory.get_material_count(StringName(id)) == int(saved_materials[id])
	_check(inventory.get_owned_ids().map(func(id: StringName) -> String: return String(id)) == saved_inventory["owned"]
			and inventory.get_quick_slot_ids().map(func(id: StringName) -> String: return String(id)) == saved_inventory["quick_slots"] and materials_match,
			"and every tool, quick slot and material")
	var old := JSON.parse_string(json) as Dictionary
	old.erase("gathering")
	(old["inventory"] as Dictionary).erase("materials")
	await _load_level()
	SaveGame.find(self).from_dict(old)
	await _frames(2)
	_check(inventory.get_material_counts().is_empty() and _target("WillowmerePond/Jetty").is_available() and inventory.has_item(&"garden_shovel"),
			"a save from before Phase 5H tools (no materials, no gathering) loads cleanly: no materials, nothing repaired")
