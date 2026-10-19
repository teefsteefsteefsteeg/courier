extends SceneTree
## Assemble Blender-authored GLBs into reusable colliding props and a playable region.
## No visual geometry is generated here; primitive shapes are collision only.

const MODELS := "res://assets/generated/blender/"
const SCENES := "res://scenes/generated/"
var scene_root: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCENES)
	_make_props()
	_region()
	quit()


func add(parent: Node, node: Node, title: String, at := Vector3.ZERO) -> Node:
	node.name = title
	parent.add_child(node)
	if node is Node3D:
		node.position = at
	node.owner = scene_root
	return node


func instance(parent: Node, path: String, title: String, at := Vector3.ZERO) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	add(parent, node, title, at)
	return node


func box(parent: Node, title: String, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	add(parent, body, title, at)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add(body, collision, "Collision")
	return body


func pack(path: String) -> void:
	var scene := PackedScene.new()
	var err := scene.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(scene, path)
	print("BLENDER_SCENE ", path, " error=", err)
	if err != OK:
		push_error("Could not save generated scene: " + path)
	scene_root.free()


func _make_props() -> void:
	var specs := {
		"crypt_floor_4m": [Vector3(4, .24, 4), Vector3(0, -.12, 0)],
		"crypt_wall_4m": [Vector3(4.12, 3.04, .82), Vector3(0, 1.52, 0)],
		"crypt_pillar": [Vector3(1.15, 2.9, 1.15), Vector3(0, 1.45, 0)],
		"sentinel_rune_stone": [Vector3(1.3, 2.35, 1.1), Vector3(0, 1.17, 0)],
		"amethyst_cluster": [Vector3(1.35, 1.6, 1.35), Vector3(0, .8, 0)],
		"boss_heart_altar": [Vector3(2.7, 1.6, 2.7), Vector3(0, .8, 0)],
		"crypt_brazier": [Vector3(.75, 1.75, .75), Vector3(0, .87, 0)],
		"ironbound_treasure_chest": [Vector3(1.75, 1.15, 1.0), Vector3(0, .57, 0)],
		"courier_waypost": [Vector3(.35, 2.5, .35), Vector3(0, 1.25, 0)],
		"sentinel_boss_arena": [Vector3(15.2, .24, 15.2), Vector3(0, -.12, 0)],
		"runewood_dungeon_entrance": [], "crypt_stairway": [], "wayfarer_open_gate": []
	}
	for key in specs:
		scene_root = Node3D.new()
		scene_root.name = key.to_pascal_case()
		instance(scene_root, MODELS + key + ".glb", "Model")
		var spec: Array = specs[key]
		if not spec.is_empty():
			box(scene_root, "Solid", spec[0], spec[1])
		if key == "runewood_dungeon_entrance":
			for side in [-1.0, 1.0]:
				box(scene_root, "Jamb" + str(int(side)), Vector3(3.1, 2.7, 1.6), Vector3(side * 3.0, 1.35, 0))
			box(scene_root, "Lintel", Vector3(4.3, 1.5, 1.5), Vector3(0, 3.7, 0))
			box(scene_root, "SealedPassage", Vector3(3, 3, .2), Vector3(0, 1.5, -.74))
		if key == "wayfarer_open_gate":
			for side in [-1.0, 1.0]:
				box(scene_root, "SideFence" + str(int(side)), Vector3(1.8, 2, .42), Vector3(side * 2.4, 1, 0))
		if key == "crypt_stairway":
			var body := StaticBody3D.new()
			add(scene_root, body, "WalkableRamp")
			var convex := ConvexPolygonShape3D.new()
			convex.points = PackedVector3Array([
				Vector3(-1.7, -.15, -3.25), Vector3(1.7, -.15, -3.25), Vector3(-1.7, -.15, 3), Vector3(1.7, -.15, 3),
				Vector3(-1.7, 0, -3.25), Vector3(1.7, 0, -3.25), Vector3(-1.7, 2.16, 3), Vector3(1.7, 2.16, 3)])
			var ramp := CollisionShape3D.new()
			ramp.shape = convex
			add(body, ramp, "Ramp")
			for side in [-1.0, 1.0]:
				box(scene_root, "StairSide" + str(int(side)), Vector3(.25, 3, 6), Vector3(side * 1.88, 1.5, 0))
		if key == "crypt_brazier" or key == "amethyst_cluster" or key == "boss_heart_altar":
			var light := OmniLight3D.new()
			light.light_color = Color(1, .57, .22) if key == "crypt_brazier" else Color(.38, .48, 1)
			light.light_energy = 2.0 if key == "crypt_brazier" else 1.0
			light.omni_range = 7.0
			add(scene_root, light, "Glow", Vector3(0, 1.8, 0))
		pack(SCENES + key + ".tscn")
	scene_root = Node3D.new()
	scene_root.name = "RunewoodPathFlags"
	instance(scene_root,MODELS+"crypt_floor_4m.glb","Model")
	# Decorative 2 cm paving uses the existing terrain collider, avoiding raised edges.
	pack(SCENES+"runewood_path_flags.tscn")


func prop(parent: Node, key: String, title: String, at: Vector3, yaw := 0.0) -> Node3D:
	var node := instance(parent, SCENES + key + ".tscn", title, at)
	node.rotation.y = yaw
	return node


func interact(parent: Node, title: String, verb: String, at: Vector3) -> void:
	var area := Interactable.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.display_name = title
	area.prompt_verb = verb
	add(parent, area, "Interactable", at)
	var shape := SphereShape3D.new()
	shape.radius = .85
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add(area, collision, "Range", Vector3.UP * .8)


func zone(parent: Node, title: String, display: String, at: Vector3, size: Vector3, priority: int) -> void:
	var z := LocationZone.new()
	z.display_name = display
	z.subtitle = "Runewood Escarpment" if priority == 12 else "The Sentinel's sealed sanctuary"
	z.location_id = &"runewood_crypt"
	z.zone_priority = priority
	z.collision_layer = 0
	z.collision_mask = 2
	add(parent, z, title, at)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add(z, collision, "Bounds")


func _region() -> void:
	scene_root = Node3D.new()
	scene_root.name = "RunewoodRegion"
	scene_root.set_script(load("res://scripts/world/runewood_region.gd"))
	var outside := Node3D.new()
	add(scene_root, outside, "Exterior")
	var entrance := prop(outside, "runewood_dungeon_entrance", "Entrance", Vector3(33, 0, -34))
	interact(entrance, "Runewood Crypt", "Descend into", Vector3(0, 0, 1.4))
	var marker := WorldLocation.new()
	marker.location_id = &"runewood_crypt"
	marker.display_name = "Runewood Crypt"
	marker.subtitle = "Ancient stairs beneath the northeast ruins"
	marker.kind = WorldLocation.Kind.CLEARING
	marker.discover_radius = 10
	add(outside, marker, "MapLocation", Vector3(33, 0, -32))
	zone(outside, "RuinsZone", "Runewood Crypt", Vector3(33, 1, -31), Vector3(19, 5, 18), 12)
	for spec in [[Vector3(28,0,-31),.4], [Vector3(38,0,-31),-.5]]:
		prop(outside, "sentinel_rune_stone", "RuneStone" + str(outside.get_child_count()), spec[0], spec[1])
	for pos: Vector3 in [Vector3(30,0,-32),Vector3(36,0,-32)]:
		prop(outside,"crypt_brazier","GateFlame" + str(outside.get_child_count()),pos)
	prop(outside,"amethyst_cluster","ExteriorCrystals",Vector3(38.5,0,-35))
	prop(outside,"courier_waypost","RuinsWaypost",Vector3(24,0,-24),-.6)
	# Raised, shallow flagstones lead off the forest lane into the new region.
	for i in 8:
		var path := prop(outside, "runewood_path_flags", "Trail%02d" % i, Vector3(18 + i * 2.05, .025, -22 - i * 1.4))
		path.scale = Vector3(.62, .12, .62)
		path.rotation.y = -.6
	var dungeon := Node3D.new()
	add(scene_root, dungeon, "Dungeon", Vector3(0, -40, 0))
	# Entry hall: north/west walls are high; camera-side parapets are cut away.
	for x in [-6, -2, 2, 6]:
		for z in [-6, -2, 2, 6]:
			prop(dungeon,"crypt_floor_4m","HallFloor%d_%d" % [x,z],Vector3(x,0,z))
	for x in [-6, -2, 2, 6]:
		if abs(x) > 2:
			prop(dungeon,"crypt_wall_4m","NorthWall%d"%x,Vector3(x,0,-8))
		var south := prop(dungeon,"crypt_wall_4m","SouthParapet%d"%x,Vector3(x,0,8))
		if abs(x) <= 2:
			south.free() # Stairway gap remains clear before packing the scene.
		else:
			south.scale.y=.24
	for z in [-6,-2,2,6]:
		prop(dungeon,"crypt_wall_4m","WestWall%d"%z,Vector3(-8,0,z),PI/2)
		var east := prop(dungeon,"crypt_wall_4m","EastParapet%d"%z,Vector3(8,0,z),PI/2)
		east.scale.y=.24
	for x in [-2.85,2.85]:
		var edge := prop(dungeon,"crypt_wall_4m","StairOpeningEdge"+str(x),Vector3(x,0,8))
		edge.scale = Vector3(.54,.24,1)
	for pos: Vector3 in [Vector3(-5.5,0,-5.5),Vector3(5.5,0,-5.5),Vector3(-5.5,0,5.5),Vector3(5.5,0,5.5)]:
		prop(dungeon,"crypt_pillar","HallPillar"+str(dungeon.get_child_count()),pos)
	prop(dungeon,"crypt_stairway","DescentStairs",Vector3(0,0,10.8))
	var landing := prop(dungeon,"crypt_floor_4m","ReturnLanding",Vector3(0,2.16,15.8))
	interact(landing,"Willowmere surface", "Return to", Vector3(0,0,.2))
	var exit_arch := prop(dungeon,"runewood_dungeon_entrance","ReturnArch",Vector3(0,2.16,17.6),PI)
	exit_arch.scale = Vector3.ONE * .6
	for x in [-2.0,2.0]:
		var rail := prop(dungeon,"crypt_wall_4m","LandingRail"+str(int(x)),Vector3(x,2.16,15.8),PI/2)
		rail.scale.y=.24
	for z in [-10,-14]:
		prop(dungeon,"crypt_floor_4m","CorridorFloor%d"%z,Vector3(0,0,z))
		for x in [-2.5,2.5]:
			var wall := prop(dungeon,"crypt_wall_4m","CorridorWall%d_%d"%[x,z],Vector3(x,0,z),PI/2)
			if x > 0:
				wall.scale.y = .24
	var arena := prop(dungeon,"sentinel_boss_arena","BossArena",Vector3(0,0,-23.5))
	for x in [-6,-2,2,6]:
		for z in [-6,-2,2,6]:
			prop(arena,"crypt_floor_4m","BorderFlags%d_%d"%[x,z],Vector3(x,-.035,z))
	prop(dungeon,"boss_heart_altar","HeartAltar",Vector3(0,0,-26))
	# Enclosed arena boundary: side walls plus segmented far wall; low near edges.
	for x in [-6,-2,2,6]:
		prop(dungeon,"crypt_wall_4m","ArenaNorth%d"%x,Vector3(x,0,-31.5))
	for z in [-29.5,-25.5,-21.5,-17.5]:
		prop(dungeon,"crypt_wall_4m","ArenaWest%d"%z,Vector3(-8,0,z),PI/2)
		var east := prop(dungeon,"crypt_wall_4m","ArenaEast%d"%z,Vector3(8,0,z),PI/2)
		east.scale.y=.24
	for x in [-6,6]:
		var near := prop(dungeon,"crypt_wall_4m","ArenaSouth%d"%x,Vector3(x,0,-15.5))
		near.scale.y=.24
	# Subfloor is square: no fall-through corners behind the circular patterned arena.
	box(arena,"ArenaSubfloor",Vector3(16,.2,16),Vector3(0,-.22,0))
	for i in 6:
		var a := float(i)*TAU/6
		prop(dungeon,"sentinel_rune_stone","ArenaRune%d"%i,Vector3(cos(a)*6.1,0,-23.5+sin(a)*6.1),-a-PI/2)
	for pos: Vector3 in [Vector3(-6.8,0,-28),Vector3(6.8,0,-28),Vector3(-6.8,0,-19)]:
		prop(dungeon,"amethyst_cluster","CryptCrystal"+str(dungeon.get_child_count()),pos)
	for pos: Vector3 in [Vector3(-6,0,3),Vector3(6,0,3),Vector3(-6,0,-3),Vector3(6,0,-3),Vector3(1.45,0,-12),Vector3(-5,0,-18),Vector3(5,0,-18)]:
		prop(dungeon,"crypt_brazier","CryptFlame"+str(dungeon.get_child_count()),pos)
	var chest := prop(dungeon,"ironbound_treasure_chest","TreasureChest",Vector3(-5,0,-1),.4)
	interact(chest,"ironbound chest", "Inspect",Vector3(0,0,.6))
	zone(dungeon,"CryptZone","The Sentinel Vault",Vector3(0,2,-7),Vector3(20,9,53),20)
	var markers := Node3D.new()
	add(scene_root,markers,"Markers")
	add(markers,Marker3D.new(),"SurfaceArrival",Vector3(33,.1,-30.5))
	add(markers,Marker3D.new(),"CryptArrival",Vector3(0,-37.6,15.5))
	# Village additions sit beside an existing lane; the central aperture stays open.
	var village := Node3D.new()
	add(scene_root,village,"VillageDetails")
	prop(village,"wayfarer_open_gate","FarmLaneGate",Vector3(-33,0,8))
	prop(village,"courier_waypost","VillageWaypost",Vector3(9.5,0,-7),.5)
	pack(SCENES + "runewood_region.tscn")
