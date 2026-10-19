extends SceneTree
## Phase 5H: builds the scenes for the RPG tool interactions from existing art (Quaternius
## and MegaKit nature, KayKit RPG Tools Bits) plus a few primitive meshes:
##   res://scenes/world/tools/harvest_tree.tscn   marked tree, woodcutting axe -> wood
##   res://scenes/world/tools/ore_rock.tscn       ore rock, pickaxe -> stone (+ iron ore)
##   res://scenes/world/tools/dig_spot.tscn       soft soil, shovel -> clay
##   res://scenes/world/tools/broken_fence.tscn   hammer + wood repair
##   res://scenes/world/tools/crumbled_wall.tscn  trowel + stone and clay repair
##   res://scenes/locations/willowmere_pond.tscn  pond, broken jetty, jetty fishing spot, dig spots
##   res://scenes/locations/tool_stall.tscn       the Toolwright's stall and Toolwright Hobb
## target_id values are set per instance where the village places them (the pond's own
## targets are fixed here). Change this generator, not the scenes, then re-run:
##   godot --headless --path . --script res://tools/generate_tool_sites.gd

const OUT_TOOLS := "res://scenes/world/tools/"
const POND_SCENE := "res://scenes/locations/willowmere_pond.tscn"
const STALL_SCENE := "res://scenes/locations/tool_stall.tscn"
const TOOLS := "res://assets/models/kaykit_rpg_tools/"
const MATERIALS := "res://assets/materials/buildings/"
const MATS := "res://data/materials/"

const INTERACTABLE := preload("res://scripts/interaction/interactable.gd")
const HARVEST := preload("res://scripts/tools/harvest_node.gd")
const REPAIR := preload("res://scripts/tools/repair_site.gd")
const FISHING := preload("res://scripts/tools/fishing_spot.gd")
const POND := preload("res://scripts/world/pond.gd")
const STALL := preload("res://scripts/world/tool_stall.gd")
const WORLD_LOCATION := preload("res://scripts/world/world_location.gd")

## The tree model and trunk of scenes/props/nature/common_tree_2.tscn, without that prop's
## CameraOccluder: a tree being chopped always stands next to the courier and would fade.
const TREE_MODEL := "res://assets/models/quaternius/ultimate_nature/CommonTree_2.fbx"
const BOULDER := "res://scenes/props/megakit/boulder_2.tscn"
const PEBBLES := ["res://assets/models/megakit/nature/Pebble_Round_1.gltf", "res://assets/models/megakit/nature/Pebble_Square_2.gltf", "res://assets/models/megakit/nature/Pebble_Round_3.gltf"]
const WOOD_LOG := "res://assets/models/quaternius/ultimate_nature/WoodLog.fbx"
const FENCE := "res://scenes/props/megakit/wood_fence.tscn"
const FENCE_MODEL := "res://assets/models/megakit/village/Prop_WoodenFence_Single.gltf"
const WALL_FULL := "res://scenes/props/env/ruin_wall.tscn"
const WALL_HALF := "res://scenes/props/env/ruin_wall_half.tscn"
const GRASS := "res://assets/models/quaternius/ultimate_nature/Grass_2.fbx"
const ROCK_FLAT := "res://scenes/props/env/rock_flat.tscn"
const NPC_SCENE := "res://scenes/npc/characters/toolwright_hobb.tscn"
## The courier's InteractionDetector sphere (scenes/player/player.tscn).
const DETECTOR_RADIUS := 1.4

var root_node: Node3D
var _cache := {}
var _mats := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_TOOLS)
	_harvest_tree()
	_ore_rock()
	_dig_spot()
	_broken_fence()
	_crumbled_wall()
	_pond()
	_stall()
	quit()


# --- harvestable resources -----------------------------------------------------------------

func _harvest_tree() -> void:
	var node := _root(HARVEST, "HarvestTree")
	node.set(&"display_name", "Marked Tree")
	node.set(&"required_tool", ItemDefinition.ToolType.WOOD_AXE)
	node.set(&"verb", "Chop")
	node.set(&"action", &"tool_chop")
	node.set(&"strokes", 4)
	node.set(&"stroke_speed", 1.35)
	# Every reach covers the prompt's range (interaction radius + the courier's 1.4 m detector):
	# ToolUser cancels a job once the courier is farther than reach.
	node.set(&"reach", _reach(1.1))
	node.set(&"chip_color", Color(0.62, 0.45, 0.26))
	node.set(&"yield_material", load(MATS + "wood.tres"))
	node.set(&"yield_min", 2)
	node.set(&"yield_max", 4)
	node.set(&"respawn_seconds", 240.0)
	node.set(&"activity", &"chop")
	node.set(&"depleted_name", "Tree Stump")
	var standing := _group(root_node, "Standing")
	var trunk := StaticBody3D.new()
	_add(standing, trunk, "Tree", Transform3D.IDENTITY)
	_instance(TREE_MODEL, trunk, "Model").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.3), Vector3.ZERO)
	_collider(trunk, _cylinder_shape(0.4, 1.6), Vector3(0, 0.8, 0))
	# The woodcutters' blaze: a pale notch on the trunk (two faces, so the camera sees one).
	for spec in [[Vector3(0, 1.05, 0.27), 0.0], [Vector3(0.27, 1.05, 0), PI / 2]]:
		var blaze := _box("Blaze", Vector3(0.2, 0.3, 0.03), Color(0.93, 0.88, 0.74), standing)
		blaze.transform = Transform3D(Basis(Vector3.UP, spec[1]), spec[0])
	var depleted := _group(root_node, "Depleted")
	var stump := StaticBody3D.new()
	_add(depleted, stump, "Stump", Transform3D.IDENTITY)
	_cylinder("Bark", 0.3, 0.36, 0.42, Color(0.36, 0.25, 0.16), stump).position.y = 0.21
	_cylinder("Rings", 0.27, 0.27, 0.02, Color(0.82, 0.68, 0.46), stump).position.y = 0.43
	_collider(stump, _cylinder_shape(0.36, 0.45), Vector3(0, 0.22, 0))
	var felled := _instance(WOOD_LOG, depleted, "FelledLog")
	felled.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-30)).scaled(Vector3.ONE * 0.9), Vector3(1.1, 0, 0.5))
	_interactable(root_node, 1.1, 0.8)
	node.set(&"standing_visual", standing)
	node.set(&"depleted_visual", depleted)
	node.set(&"shake_node", standing)
	_pack(OUT_TOOLS + "harvest_tree.tscn")


func _ore_rock() -> void:
	var node := _root(HARVEST, "OreRock")
	node.set(&"display_name", "Ore Rock")
	node.set(&"required_tool", ItemDefinition.ToolType.PICKAXE)
	node.set(&"verb", "Mine")
	node.set(&"action", &"tool_mine")
	node.set(&"strokes", 4)
	node.set(&"stroke_speed", 1.35)
	node.set(&"reach", _reach(1.3))
	node.set(&"chip_color", Color(0.55, 0.55, 0.58))
	node.set(&"yield_material", load(MATS + "stone.tres"))
	node.set(&"yield_min", 2)
	node.set(&"yield_max", 3)
	node.set(&"bonus_material", load(MATS + "iron_ore.tres"))
	node.set(&"bonus_chance", 0.5)
	node.set(&"respawn_seconds", 300.0)
	node.set(&"activity", &"mine")
	node.set(&"depleted_name", "Rubble")
	var standing := _group(root_node, "Standing")
	var boulder := _scene(BOULDER)
	_add(standing, boulder, "Boulder", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.3), Vector3.ZERO))
	# Rust-red ore showing through the rock, on the faces the camera sees.
	var ore := Color(0.74, 0.36, 0.18)
	for spec in [[Vector3(0.62, 0.55, 0.32), 20.0], [Vector3(0.3, 0.85, 0.55), -35.0], [Vector3(0.72, 0.3, -0.15), 55.0], [Vector3(-0.2, 0.62, 0.68), 10.0], [Vector3(0.05, 1.05, 0.2), 70.0]]:
		var nugget := _box("Ore", Vector3(0.2, 0.14, 0.18), ore, standing, 0.5)
		nugget.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(spec[1]), deg_to_rad(spec[1] * 1.7), 0)), spec[0])
	var depleted := _group(root_node, "Depleted")
	var spots := [Vector3(-0.3, 0, 0.2), Vector3(0.35, 0, -0.1), Vector3(0.05, 0, 0.45)]
	for i in PEBBLES.size():
		var pebble := _instance(PEBBLES[i], depleted, "Rubble%d" % i)
		pebble.transform = Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3.ONE * 0.7), spots[i])
	_interactable(root_node, 1.3, 0.6)
	node.set(&"standing_visual", standing)
	node.set(&"depleted_visual", depleted)
	node.set(&"shake_node", standing)
	_pack(OUT_TOOLS + "ore_rock.tscn")


func _dig_spot() -> void:
	var node := _root(HARVEST, "DigSpot")
	node.set(&"display_name", "Soft Soil")
	node.set(&"required_tool", ItemDefinition.ToolType.SHOVEL)
	node.set(&"verb", "Dig")
	node.set(&"action", &"tool_dig")
	node.set(&"strokes", 3)
	node.set(&"stroke_speed", 1.25)
	node.set(&"reach", _reach(0.9))
	node.set(&"chip_color", Color(0.42, 0.3, 0.2))
	node.set(&"yield_material", load(MATS + "clay.tres"))
	node.set(&"yield_min", 1)
	node.set(&"yield_max", 2)
	node.set(&"respawn_seconds", 180.0)
	node.set(&"activity", &"dig")
	node.set(&"depleted_name", "Dug-up Soil")
	var standing := _group(root_node, "Standing")
	var mound := _sphere("Mound", 0.6, 0.36, Color(0.43, 0.3, 0.2), standing)
	mound.position.y = 0.02
	for spec in [Vector3(0.28, 0.12, 0.2), Vector3(-0.22, 0.1, 0.3)]:
		_sphere("Clay", 0.1, 0.12, Color(0.72, 0.42, 0.29), standing).position = spec
	# A marker stake with a red rag, so the soft patch reads as diggable.
	var stake := _box("Stake", Vector3(0.05, 0.6, 0.05), Color(0.55, 0.38, 0.22), standing)
	stake.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(8)), Vector3(-0.45, 0.3, -0.2))
	_box("Rag", Vector3(0.14, 0.09, 0.02), Color(0.8, 0.2, 0.16), standing).position = Vector3(-0.38, 0.52, -0.2)
	var depleted := _group(root_node, "Depleted")
	_cylinder("Hole", 0.42, 0.42, 0.02, Color(0.16, 0.11, 0.08), depleted).position.y = 0.015
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.6
	torus.material = _color_material(Color(0.4, 0.28, 0.18))
	rim.mesh = torus
	_add(depleted, rim, "Rim", Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.25, 1)), Vector3(0, 0.03, 0)))
	_interactable(root_node, 0.9, 0.5)
	node.set(&"standing_visual", standing)
	node.set(&"depleted_visual", depleted)
	node.set(&"shake_node", standing)
	_pack(OUT_TOOLS + "dig_spot.tscn")


# --- repairable structures -----------------------------------------------------------------

func _broken_fence() -> void:
	var node := _root(REPAIR, "BrokenFence")
	_repair_settings(node, "Broken Fence", ItemDefinition.ToolType.HAMMER, &"tool_hammer", {&"wood": 3}, 25, 4)
	node.set(&"chip_color", Color(0.62, 0.45, 0.26))
	var damaged := _group(root_node, "Damaged")
	_add(damaged, _scene(FENCE), "Standing", Transform3D(Basis.IDENTITY, Vector3(-1.1, 0, 0)))
	# The fallen panel is the bare model: no collider to trip over.
	var fallen := _instance(FENCE_MODEL, damaged, "Fallen")
	fallen.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(12)) * Basis(Vector3.RIGHT, deg_to_rad(-82)) * Basis.IDENTITY.scaled(Vector3.ONE * 1.0658), Vector3(1.2, 0.08, 0.55))
	for spec in [[Vector3(0.5, 0.04, 1.2), 30.0], [Vector3(1.9, 0.04, 1.0), -50.0]]:
		var plank := _box("Plank", Vector3(1.0, 0.05, 0.14), Color(0.6, 0.44, 0.28), damaged)
		plank.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(spec[1])), spec[0])
	var repaired := _group(root_node, "Repaired")
	_add(repaired, _scene(FENCE), "Left", Transform3D(Basis.IDENTITY, Vector3(-1.1, 0, 0)))
	_add(repaired, _scene(FENCE), "Right", Transform3D(Basis.IDENTITY, Vector3(1.1, 0, 0)))
	_interactable(root_node, 1.3, 0.6, Vector3(0.9, 0, 0.6))
	node.set(&"damaged_visual", damaged)
	node.set(&"repaired_visual", repaired)
	node.set(&"shake_node", damaged)
	_pack(OUT_TOOLS + "broken_fence.tscn")


func _crumbled_wall() -> void:
	var node := _root(REPAIR, "CrumbledWall")
	_repair_settings(node, "Crumbled Wall", ItemDefinition.ToolType.TROWEL, &"tool_trowel", {&"stone": 3, &"clay": 1}, 35, 6)
	node.set(&"verb", "Re-set")
	node.set(&"chip_color", Color(0.6, 0.6, 0.6))
	var damaged := _group(root_node, "Damaged")
	_add(damaged, _scene(WALL_HALF), "Remaining", Transform3D(Basis.IDENTITY, Vector3(-0.5, 0, 0)))
	for i in PEBBLES.size():
		var pebble := _instance(PEBBLES[i], damaged, "Fallen%d" % i)
		pebble.transform = Transform3D(Basis(Vector3.UP, i * 2.1).scaled(Vector3.ONE * 0.9), Vector3(0.45 + i * 0.32, 0, 0.45 - i * 0.2))
	var block := _box("Block", Vector3(0.5, 0.3, 0.28), Color(0.55, 0.6, 0.5), damaged)
	block.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.6, 0.15, 0.9))
	var repaired := _group(root_node, "Repaired")
	_add(repaired, _scene(WALL_FULL), "Wall", Transform3D.IDENTITY)
	_interactable(root_node, 1.3, 0.7, Vector3(0.4, 0, 0.8))
	node.set(&"damaged_visual", damaged)
	node.set(&"repaired_visual", repaired)
	node.set(&"shake_node", damaged)
	_pack(OUT_TOOLS + "crumbled_wall.tscn")


func _repair_settings(node: Node, title: String, tool: ItemDefinition.ToolType, clip: StringName, cost: Dictionary, gold: int, reputation: int) -> void:
	node.set(&"display_name", title)
	node.set(&"required_tool", tool)
	node.set(&"verb", "Repair")
	node.set(&"action", clip)
	node.set(&"strokes", 4)
	node.set(&"stroke_speed", 1.6)
	node.set(&"reach", _reach(1.3))
	var materials: Dictionary[StringName, int] = {}
	for id in cost:
		materials[id] = cost[id]
	node.set(&"materials", materials)
	node.set(&"reward_gold", gold)
	node.set(&"reward_reputation", reputation)


# --- Willowmere Pond -----------------------------------------------------------------------

func _pond() -> void:
	root_node = Node3D.new()
	root_node.name = "WillowmerePond"
	var pond := Node3D.new()
	pond.set_script(POND)
	pond.set(&"radius_x", 4.6)
	pond.set(&"radius_z", 3.6)
	pond.set(&"outline_seed", 7)
	pond.set(&"jetty_angle_degrees", 90.0)
	pond.set(&"jetty_width", 1.6)
	pond.set(&"jetty_length", 2.8)
	var fish: Array[MaterialItem] = [load(MATS + "pond_perch.tres"), load(MATS + "silver_trout.tres"), load(MATS + "golden_carp.tres")]
	pond.set(&"fish", fish)
	pond.set(&"fish_weights", PackedFloat32Array([62.0, 30.0, 8.0]))
	pond.set(&"rare_from", 2)
	_add(root_node, pond, "Pond", Transform3D.IDENTITY)
	# The jetty runs from the south bank (+Z) towards the middle.
	var shore: float = pond.call(&"shore_radius", PI / 2)
	var base := Vector3(0, 0, shore + 0.3)
	var tip := Vector3(0, 0, shore - 2.8)
	var jetty := Node3D.new()
	jetty.set_script(REPAIR)
	_add(root_node, jetty, "Jetty", Transform3D.IDENTITY)
	_repair_settings(jetty, "Pond Jetty", ItemDefinition.ToolType.HAMMER, &"tool_hammer", {&"wood": 4}, 30, 5)
	jetty.set(&"target_id", &"pond_jetty")
	jetty.set(&"strokes", 5)
	jetty.set(&"chip_color", Color(0.62, 0.45, 0.26))
	var length := base.z - tip.z
	var damaged := _group(jetty, "Damaged")
	var repaired := _group(jetty, "Repaired")
	var plank_count := int(length / 0.32)
	for i in plank_count:
		var z := base.z - 0.16 - i * 0.32
		_box("Plank", Vector3(1.5, 0.06, 0.28), Color(0.6, 0.43, 0.27), repaired).position = Vector3(0, 0.1, z)
		# Broken: every third plank missing, the rest loose and askew.
		if i % 3 != 1:
			var loose := _box("Plank", Vector3(1.5 - (i % 2) * 0.4, 0.06, 0.28), Color(0.5, 0.37, 0.24), damaged)
			loose.transform = Transform3D(Basis(Vector3.UP, deg_to_rad((i % 3 - 1) * 9.0)) * Basis(Vector3.BACK, deg_to_rad((i % 2) * 7.0)), Vector3((i % 2) * 0.2, 0.09, z))
	for group in [damaged, repaired]:
		for post_x in [-0.72, 0.72]:
			for post_z in [base.z - 0.2, (base.z + tip.z) * 0.5, tip.z + 0.15]:
				var tilt := deg_to_rad(10.0 if group == damaged and post_z == tip.z + 0.15 else 0.0)
				var post := _cylinder("Post", 0.07, 0.08, 0.7, Color(0.42, 0.3, 0.2), group)
				post.transform = Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(post_x, 0.15, post_z))
	# A plank lies in the water by the broken jetty.
	var adrift := _box("Adrift", Vector3(1.2, 0.05, 0.26), Color(0.5, 0.37, 0.24), damaged)
	adrift.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(1.2, 0.06, tip.z + 0.6))
	var blocker := StaticBody3D.new()
	_add(jetty, blocker, "Blocker", Transform3D.IDENTITY)
	_collider(blocker, _box_shape(Vector3(1.9, 1.6, 0.3)), Vector3(0, 0.8, shore + 0.1))
	_interactable(jetty, 1.2, 0.6, Vector3(0, 0, shore + 1.1))
	jetty.set(&"damaged_visual", damaged)
	jetty.set(&"repaired_visual", repaired)
	jetty.set(&"shake_node", damaged)
	jetty.set(&"blockers", Array([blocker], TYPE_OBJECT, &"CollisionObject3D", null))
	# Fishing from the end of the repaired jetty: better odds of a golden carp.
	var spot := Node3D.new()
	spot.set_script(FISHING)
	_add(root_node, spot, "JettySpot", Transform3D(Basis.IDENTITY, Vector3(0, 0, tip.z + 0.4)))
	spot.set(&"target_id", &"pond_jetty_spot")
	spot.set(&"display_name", "the Jetty")
	spot.set(&"pond", pond)
	spot.set(&"catch_bonus", 3.0)
	spot.set(&"reach", _reach(0.8))
	spot.set(&"requires_repair", jetty)
	var cast := Marker3D.new()
	_add(spot, cast, "CastPoint", Transform3D(Basis.IDENTITY, Vector3(0, 0, -2.0)))
	spot.set(&"cast_point", cast)
	_interactable(spot, 0.8, 0.6)
	jetty.set(&"unlocks", Array([spot], TYPE_OBJECT, &"Node", null))
	# Soft soil on the banks.
	for spec in [["DigWest", PI * 0.78, 1.5, &"pond_dig_west"], ["DigNorth", PI * 1.55, 1.6, &"pond_dig_north"]]:
		var r: float = pond.call(&"shore_radius", spec[1]) + float(spec[2])
		var dig := _scene(OUT_TOOLS + "dig_spot.tscn")
		_add(root_node, dig, spec[0], Transform3D(Basis.IDENTITY, Vector3(cos(spec[1]) * r, 0, sin(spec[1]) * r)))
		dig.set(&"target_id", spec[3])
	# Reeds and stones along the bank, a bucket and rope by the jetty (KayKit RPG Tools).
	var dressing := _group(root_node, "Dressing")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 14:
		var a := TAU * i / 14.0 + rng.randf_range(-0.12, 0.12)
		if absf(angle_difference(a, PI / 2)) < 0.45:
			continue
		var r: float = pond.call(&"shore_radius", a) + rng.randf_range(-0.15, 0.35)
		var reed := _instance(GRASS, dressing, "Reeds%d" % i)
		reed.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, rng.randf_range(1.6, 2.4), 1.2)), Vector3(cos(a) * r, 0, sin(a) * r))
	for spec in [[PI * 0.08, 0.6], [PI * 1.2, 0.5], [PI * 1.85, 0.7]]:
		var r: float = pond.call(&"shore_radius", spec[0]) + 0.5
		var stone := _scene(ROCK_FLAT)
		_add(dressing, stone, "BankStone", Transform3D(Basis(Vector3.UP, spec[0]).scaled(Vector3.ONE * float(spec[1])), Vector3(cos(spec[0]) * r, 0, sin(spec[0]) * r)))
	_instance(TOOLS + "bucket_metal.gltf", dressing, "Bucket").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.6), Vector3(1.3, 0, shore + 1.0))
	_instance(TOOLS + "rope_bundle_B.gltf", dressing, "Rope").transform = Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3.ONE * 0.55), Vector3(-1.35, 0, shore + 0.9))
	var location := Marker3D.new()
	location.set_script(WORLD_LOCATION)
	_add(root_node, location, "Location", Transform3D.IDENTITY)
	location.set(&"location_id", &"willowmere_pond")
	location.set(&"display_name", "Willowmere Pond")
	location.set(&"subtitle", "Fish, clay and a broken jetty")
	location.set(&"kind", WorldLocation.Kind.CLEARING)
	location.set(&"discover_radius", 9.0)
	_pack(POND_SCENE)


# --- the Toolwright's stall ----------------------------------------------------------------

func _stall() -> void:
	root_node = Node3D.new()
	root_node.name = "ToolStall"
	root_node.set_script(STALL)
	root_node.set(&"catalog", load("res://data/shops/toolwright.tres"))
	# The stall faces +Z: counter in front, Hobb behind it, an awning over both.
	var stall := StaticBody3D.new()
	_add(root_node, stall, "Counter", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.6)))
	_mat_box("Top", Vector3(2.2, 0.08, 0.62), Vector3(0, 0.96, 0), "timber", stall)
	_mat_box("Front", Vector3(2.16, 0.92, 0.06), Vector3(0, 0.46, 0.27), "planks", stall)
	_mat_box("SideL", Vector3(0.06, 0.92, 0.58), Vector3(-1.05, 0.46, 0), "planks", stall)
	_mat_box("SideR", Vector3(0.06, 0.92, 0.58), Vector3(1.05, 0.46, 0), "planks", stall)
	_collider(stall, _box_shape(Vector3(2.2, 1.0, 0.62)), Vector3(0, 0.5, 0))
	# Small tools laid out on the counter.
	var top := 1.0
	for spec in [["hammer", Vector3(-0.75, top + 0.04, 0.05), Vector3(90, 0, 70)], ["saw", Vector3(-0.15, top + 0.03, -0.05), Vector3(90, 0, 10)],
			["wrench_A", Vector3(0.35, top + 0.02, 0.12), Vector3(90, 0, -40)], ["chisel", Vector3(0.6, top + 0.03, -0.1), Vector3(90, 0, 80)],
			["pencil_A_long", Vector3(0.82, top + 0.02, 0.12), Vector3(90, 0, 20)], ["journal_open", Vector3(-0.42, top + 0.01, -0.18), Vector3(0, 15, 0)],
			["nail", Vector3(0.15, top + 0.02, 0.2), Vector3(90, 0, 0)], ["screw_A", Vector3(0.22, top + 0.02, 0.24), Vector3(90, 0, 45)]]:
		var piece := _instance(TOOLS + spec[0] + ".gltf", stall, String(spec[0]).to_pascal_case())
		var euler: Vector3 = spec[2]
		piece.transform = Transform3D(Basis.from_euler(euler * PI / 180.0).scaled(Vector3.ONE * 0.45), spec[1])
	# Awning: four posts and a sloping plank roof.
	var awning := _group(root_node, "Awning")
	for post_x in [-1.2, 1.2]:
		for post_z in [-0.9, 1.0]:
			_mat_box("Post", Vector3(0.1, 2.4 if post_z < 0 else 2.1, 0.1), Vector3(post_x, 1.2 if post_z < 0 else 1.05, post_z), "timber", awning)
	var roof := _mat_box("Roof", Vector3(2.7, 0.06, 2.3), Vector3.ZERO, "planks", awning)
	roof.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8)), Vector3(0, 2.28, 0.05))
	_instance(TOOLS + "lantern.gltf", awning, "Lantern").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), Vector3(1.1, 1.62, 1.0))
	# Anvil on a block and a grindstone either side of the stall; a rack of long tools.
	var anvil := StaticBody3D.new()
	_add(root_node, anvil, "Anvil", Transform3D(Basis(Vector3.UP, deg_to_rad(20)), Vector3(-1.95, 0, 0.9)))
	_mat_box("Block", Vector3(0.6, 0.45, 0.6), Vector3(0, 0.225, 0), "timber", anvil)
	_instance(TOOLS + "anvil.gltf", anvil, "Model").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), Vector3(0, 0.45, 0))
	_instance(TOOLS + "tongs.gltf", anvil, "Tongs").transform = Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0.3)).scaled(Vector3.ONE * 0.4), Vector3(0.05, 0.86, 0.12))
	_collider(anvil, _box_shape(Vector3(0.8, 0.9, 0.6)), Vector3(0, 0.45, 0))
	var grind := StaticBody3D.new()
	_add(root_node, grind, "Grindstone", Transform3D(Basis(Vector3.UP, deg_to_rad(-75)), Vector3(1.95, 0, 0.7)))
	_instance(TOOLS + "grindstone.gltf", grind, "Model").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.55), Vector3(0, 0.41, 0))
	_collider(grind, _box_shape(Vector3(1.05, 0.9, 0.85)), Vector3(0, 0.45, 0))
	var rack := StaticBody3D.new()
	_add(root_node, rack, "ToolRack", Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.25)))
	_mat_box("Base", Vector3(2.0, 0.1, 0.4), Vector3(0, 0.05, 0), "timber", rack)
	_mat_box("Bar", Vector3(2.0, 0.08, 0.08), Vector3(0, 1.15, -0.12), "timber", rack)
	for upright_x in [-0.95, 0.95]:
		_mat_box("Upright", Vector3(0.08, 1.2, 0.08), Vector3(upright_x, 0.6, -0.12), "planks", rack)
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-8))
	var rack_x := -0.7
	for tool in ["axe", "pickaxe", "shovel", "trowel", "mallet"]:
		_instance(TOOLS + tool + ".gltf", rack, tool.to_pascal_case()).transform = Transform3D(lean.scaled(Vector3.ONE * 0.6), Vector3(rack_x, 0.32, 0.02))
		rack_x += 0.35
	_collider(rack, _box_shape(Vector3(2.0, 1.2, 0.45)), Vector3(0, 0.6, 0))
	var dressing := _group(root_node, "Dressing")
	_instance(TOOLS + "blueprint_stacked.gltf", dressing, "Blueprints").transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3.ONE * 0.35), Vector3(-1.6, 0, 1.75))
	_instance(TOOLS + "rope_bundle_A.gltf", dressing, "Rope").transform = Transform3D(Basis(Vector3.UP, -0.6).scaled(Vector3.ONE * 0.5), Vector3(1.75, 0, 1.75))
	_instance(TOOLS + "bucket_metal.gltf", dressing, "Bucket").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.5), Vector3(-2.0, 0, -0.2))
	_instance(TOOLS + "torch.gltf", dressing, "Torch").transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.8), Vector3(-1.3, 0.15, 1.75))
	var merchant := (load(NPC_SCENE) as PackedScene).instantiate() as Node3D
	_add(root_node, merchant, "Merchant", Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.25)))
	root_node.set(&"merchant", merchant)
	var markers := _group(root_node, "Markers")
	_add(markers, Marker3D.new(), "ShopFront", Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.75)))
	var location := Marker3D.new()
	location.set_script(WORLD_LOCATION)
	_add(root_node, location, "Location", Transform3D.IDENTITY)
	location.set(&"location_id", &"tool_stall")
	location.set(&"display_name", "Hill Smithy Tools")
	location.set(&"subtitle", "Toolwright Hobb")
	location.set(&"kind", WorldLocation.Kind.SHOP)
	location.set(&"discover_radius", 7.0)
	_pack(STALL_SCENE)


# --- helpers -------------------------------------------------------------------------------

## Reach for a target whose interaction sphere has radius: the prompt's full range (radius
## plus the courier's InteractionDetector, 1.4 m) and a little slack.
func _reach(radius: float) -> float:
	return radius + DETECTOR_RADIUS + 0.3


func _root(script: Script, node_name: String) -> Node3D:
	root_node = Node3D.new()
	root_node.name = node_name
	root_node.set_script(script)
	return root_node


func _pack(path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("%s err=%d" % [path, err])
	root_node.free()


func _add(parent: Node, node: Node, node_name: String, xform: Transform3D) -> void:
	node.name = node_name
	if node is Node3D:
		(node as Node3D).transform = xform
	parent.add_child(node, true)
	node.owner = root_node


func _group(parent: Node, group_name: String) -> Node3D:
	var node := Node3D.new()
	_add(parent, node, group_name, Transform3D.IDENTITY)
	return node


func _scene(path: String) -> Node3D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return (_cache[path] as PackedScene).instantiate() as Node3D


func _instance(path: String, parent: Node, node_name: String) -> Node3D:
	var node := _scene(path)
	_add(parent, node, node_name, Transform3D.IDENTITY)
	return node


func _interactable(parent: Node, radius: float, height: float, offset := Vector3.ZERO) -> void:
	var area := Area3D.new()
	area.set_script(INTERACTABLE)
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	_add(parent, area, "Interactable", Transform3D(Basis.IDENTITY, offset))
	var shape := SphereShape3D.new()
	shape.radius = radius
	_collider(area, shape, Vector3(0, height, 0))


func _collider(body: Node, shape: Shape3D, at: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_add(body, collider, "CollisionShape3D", Transform3D(Basis.IDENTITY, at))


func _box_shape(size: Vector3) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return shape


func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return shape


func _color_material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s/%s" % [color, metallic]
	if not _mats.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metallic
		material.roughness = 0.85 if metallic == 0.0 else 0.45
		_mats[key] = material
	return _mats[key]


func _box(node_name: String, size: Vector3, color: Color, parent: Node, metallic := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _color_material(color, metallic)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	_add(parent, node, node_name, Transform3D.IDENTITY)
	return node


func _mat_box(node_name: String, size: Vector3, at: Vector3, material: String, parent: Node) -> MeshInstance3D:
	if not _mats.has(material):
		_mats[material] = load(MATERIALS + material + ".tres")
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mats[material]
	var node := MeshInstance3D.new()
	node.mesh = mesh
	_add(parent, node, node_name, Transform3D(Basis.IDENTITY, at))
	return node


func _cylinder(node_name: String, top: float, bottom: float, height: float, color: Color, parent: Node) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = _color_material(color)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	_add(parent, node, node_name, Transform3D.IDENTITY)
	return node


func _sphere(node_name: String, radius: float, height: float, color: Color, parent: Node) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _color_material(color)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	_add(parent, node, node_name, Transform3D.IDENTITY)
	return node
