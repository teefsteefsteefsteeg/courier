extends SceneTree
## Generates the Phase 8 interiors (enterable buildings of Willowmere) as level scenes for
## WorldRouter: scenes/interiors/{armory_forge,guild_hall,rose_cottage}.tscn.
##   godot --headless --path . --script res://tools/generate_interiors.gd
##
## Each room is built from MegaKit modules (Floor_WoodDark, plaster or brick walls with a
## round door and windows) and Quaternius Fantasy Props (assets/models/fantasy_props/, CC0).
## The iso camera looks from +X/+Z, so the north and west walls are full height and the
## south and east walls are low (a cut-away), with full-height invisible colliders all round.
## The exit door is in the north wall; the courier enters in front of it ("Spawns/Entry").

const OUT := "res://scenes/interiors/"
const KIT := "res://assets/models/megakit/buildings/"
const PROPS := "res://assets/models/fantasy_props/"
const NPCS := "res://scenes/npc/characters/"
const WALL_HEIGHT := 3.1
const LOW_WALL := 0.75

var room: InteriorRoom


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_armory_forge()
	_guild_hall()
	_rose_cottage()
	quit()


# --- rooms ---------------------------------------------------------------------------

func _armory_forge() -> void:
	_begin("ArmoryForge", "Brenna's Forge")
	_room(10, 8, "Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Door_Round", "Wall_UnevenBrick_Window_Wide_Round", Color(0.42, 0.3, 0.22))
	_environment(Color(0.95, 0.72, 0.5), 0.55)
	# The forge: a brick hearth with a fire, the anvil and the smith.
	var hearth := _box("Hearth", Vector3(-3.3, 0.55, -2.9), Vector3(2.0, 1.1, 1.2), Color(0.36, 0.22, 0.17), true)
	var fire := HearthFire.new()
	fire.name = "ForgeFire"
	fire.size = 0.8
	fire.position = hearth.position + Vector3(0, 0.55, 0)
	_add(fire)
	_prop("Anvil", Vector3(-1.4, 0, -1.8), 20, true, Vector3(0.55, 0.3, 0.2))
	_prop("Whetstone", Vector3(-0.2, 0, -3.2), 0)
	_prop("Workbench", Vector3(2.4, 0, -3.25), 0, true, Vector3(1.0, 0.45, 0.5))
	_prop("Workbench_Drawers", Vector3(-4.35, 0, 0.6), 90, true, Vector3(0.5, 0.45, 1.0))
	_prop("WeaponStand", Vector3(4.2, 0, -1.2), -90, true, Vector3(0.5, 0.55, 0.7))
	_prop("WeaponStand", Vector3(4.2, 0, 1.0), -90, true, Vector3(0.5, 0.55, 0.7))
	_prop("Barrel", Vector3(-4.3, 0, 2.6), 0, true, Vector3(0.35, 0.5, 0.35))
	_prop("Crate_Wooden", Vector3(-3.6, 0, 3.3), 15, true, Vector3(0.4, 0.4, 0.4))
	_prop("Dummy", Vector3(2.6, 0, 1.9), -30, true, Vector3(0.3, 0.9, 0.3))
	_prop("Torch_Metal", Vector3(0.9, 0, -3.5), 0)
	_prop("Shield_Wooden", Vector3(1.6, 1.6, -3.78), 0)
	_prop("Sword_Bronze", Vector3(3.2, 1.6, -3.78), 90)
	_light(Vector3(0.5, 2.6, 0.0), Color(1.0, 0.8, 0.6), 1.2, 9.0)
	var smith := _npc("forgemaster_torvin", Vector3(-1.4, 0, -0.8), 200)
	room.shop_keeper = room.get_path_to(smith)
	room.shop_catalog = load("res://data/shops/forge.tres") as ShopCatalog
	_save("armory_forge")


func _guild_hall() -> void:
	_begin("GuildHall", "the Courier Guild Hall")
	_room(10, 8, "Wall_Plaster_Straight", "Wall_Plaster_Door_Round", "Wall_Plaster_Window_Wide_Round", Color(0.62, 0.5, 0.36))
	_environment(Color(0.92, 0.82, 0.68), 0.6)
	_prop("Table_Large", Vector3(0.3, 0, -1.4), 0, true, Vector3(1.45, 0.42, 0.55))
	_prop("Scroll_1", Vector3(-0.4, 0.82, -1.5), 30)
	_prop("Book_Stack_1", Vector3(1.2, 0.82, -1.6), 0)
	_prop("CandleStick_Triple", Vector3(0.2, 0.82, -1.7), 0)
	_prop("Chair_1", Vector3(0.3, 0, -2.4), 0)
	_prop("Bookcase_2", Vector3(-2.5, 0, -3.65), 0, true, Vector3(0.75, 1.3, 0.25))
	_prop("Bookcase_2", Vector3(2.5, 0, -3.65), 0, true, Vector3(0.75, 1.3, 0.25))
	_prop("Cabinet", Vector3(-4.65, 0, 0.5), 90, true, Vector3(0.2, 0.5, 0.7))
	_prop("Crate_Wooden", Vector3(-4.2, 0, 2.6), 0, true, Vector3(0.4, 0.4, 0.4))
	_prop("Crate_Wooden", Vector3(-3.4, 0, 3.1), 25, true, Vector3(0.4, 0.4, 0.4))
	_prop("Bag", Vector3(-4.0, 0.8, 2.6), 0)
	_prop("Bench", Vector3(3.6, 0, 1.6), 90, true, Vector3(0.3, 0.3, 1.0))
	_prop("Banner_1", Vector3(-4.8, 1.9, -2.0), 90)
	_prop("Chandelier", Vector3(-1.6, 3.9, 0.6), 0)
	_light(Vector3(-1.6, 2.6, 0.6), Color(1.0, 0.85, 0.6), 1.6, 8.0)
	var clerk := _npc("guild_clerk_ivy", Vector3(0.3, 0, -2.4), 0)
	clerk.position.y = 0.0
	var pickup := (load("res://scenes/gameplay/packages/package_pickup.tscn") as PackedScene).instantiate()
	pickup.name = "SealedLetterPickup"
	pickup.set(&"package_definition", load("res://data/packages/pkg_sealed_letter.tres"))
	(pickup as Node3D).position = Vector3(1.8, 0.0, -0.5)
	_add(pickup)
	_save("guild_hall")


func _rose_cottage() -> void:
	_begin("RoseCottage", "Rose Cottage")
	_room(8, 6, "Wall_Plaster_Straight", "Wall_Plaster_Door_Round", "Wall_Plaster_Window_Wide_Round", Color(0.7, 0.42, 0.36))
	_environment(Color(1.0, 0.86, 0.72), 0.6)
	var bed := _prop("Bed_Twin1", Vector3(-2.7, 0, -1.5), 0, true, Vector3(0.95, 0.4, 1.2))
	_prop("Nightstand_Shelf", Vector3(-1.4, 0, -2.5), 0)
	_prop("Candle_1", Vector3(-1.4, 0.62, -2.5), 0)
	_prop("Table_Large", Vector3(1.4, 0, 0.6), 90, true, Vector3(0.55, 0.42, 1.45))
	_prop("Chair_1", Vector3(0.6, 0, 0.2), 90)
	_prop("Chair_1", Vector3(2.2, 0, 1.0), -90)
	_prop("Mug", Vector3(1.4, 0.82, 0.3), 0)
	_prop("Table_Plate", Vector3(1.3, 0.82, 1.0), 0)
	_prop("Pot_1", Vector3(1.5, 0.82, -0.1), 0)
	_prop("Cauldron", Vector3(2.6, 0, -2.1), 0, true, Vector3(0.5, 0.45, 0.5))
	var hearth := HearthFire.new()
	hearth.name = "KitchenFire"
	hearth.size = 0.45
	hearth.light_energy = 1.4
	hearth.position = Vector3(2.6, 0.05, -2.1)
	_add(hearth)
	_prop("Shelf_Small_Bottles", Vector3(0.6, 1.4, -2.75), 0)
	_prop("Bookcase_2", Vector3(-3.65, 0, 1.6), 90, true, Vector3(0.25, 1.3, 0.75))
	_prop("Vase_2", Vector3(-3.0, 0, 2.3), 0)
	_light(Vector3(0.0, 2.5, 0.0), Color(1.0, 0.82, 0.62), 1.2, 7.0)
	var granny := _npc("granny_hollis", Vector3(0.6, 0, -0.9), 160)
	granny.position.y = 0.0
	var rest := RestBed.new()
	rest.name = "RestBed"
	rest.position = bed.position + Vector3(1.2, 0, 0.6)
	_add(rest)
	_interactable(rest, 0.9)
	_save("rose_cottage")


# --- building blocks --------------------------------------------------------------------

func _begin(node_name: String, display: String) -> void:
	room = InteriorRoom.new()
	room.name = node_name
	room.display_name = display


## A width x depth room centred on the origin: floor, walls, colliders, the exit door in the
## north wall near the west corner, and the Entry spawn in front of it.
func _room(width: int, depth: int, wall: String, door_wall: String, window_wall: String, low_color: Color) -> void:
	var w := float(width)
	var d := float(depth)
	var floors := Node3D.new()
	floors.name = "Floor"
	_add(floors)
	for ix in range(width / 2):
		for iz in range(int(ceil(d / 2.0))):
			var tile := _instance(KIT + "Floor_WoodDark.gltf", floors)
			tile.position = Vector3(-w * 0.5 + 1.0 + ix * 2.0, 0.0, -d * 0.5 + 1.0 + iz * 2.0)
	var walls := Node3D.new()
	walls.name = "Walls"
	_add(walls)
	var door_x := -w * 0.5 + 3.0
	# North wall (along X, facing +Z): windows, and the door near the west corner.
	for ix in range(width / 2):
		var x := -w * 0.5 + 1.0 + ix * 2.0
		var kind := door_wall if absf(x - door_x) < 0.5 else (window_wall if ix % 2 == 1 else wall)
		var piece := _instance(KIT + kind + ".gltf", walls)
		piece.position = Vector3(x, 0.0, -d * 0.5 + 0.3)
		if kind == window_wall:
			_window(piece)
	# West wall (along Z, facing +X).
	for iz in range(int(ceil(d / 2.0))):
		var piece := _instance(KIT + (window_wall if iz % 2 == 1 else wall) + ".gltf", walls)
		piece.position = Vector3(-w * 0.5 + 0.3, 0.0, -d * 0.5 + 1.0 + iz * 2.0)
		piece.rotation_degrees = Vector3(0, 90, 0)
		if iz % 2 == 1:
			_window(piece)
	# Low south and east walls (cut-away towards the camera), with a wooden cap.
	_box("LowWallSouth", Vector3(0, LOW_WALL * 0.5, d * 0.5 - 0.1), Vector3(w, LOW_WALL, 0.2), low_color, false)
	_box("LowWallEast", Vector3(w * 0.5 - 0.1, LOW_WALL * 0.5, 0), Vector3(0.2, LOW_WALL, d), low_color, false)
	_box("CapSouth", Vector3(0, LOW_WALL + 0.04, d * 0.5 - 0.1), Vector3(w + 0.1, 0.08, 0.3), low_color.darkened(0.35), false)
	_box("CapEast", Vector3(w * 0.5 - 0.1, LOW_WALL + 0.04, 0), Vector3(0.3, 0.08, d + 0.1), low_color.darkened(0.35), false)
	# Colliders: floor and four full-height walls.
	var body := StaticBody3D.new()
	body.name = "RoomCollision"
	_add(body)
	_shape(body, "Floor", Vector3(0, -0.1, 0), Vector3(w, 0.2, d))
	_shape(body, "North", Vector3(0, WALL_HEIGHT * 0.5, -d * 0.5 + 0.1), Vector3(w, WALL_HEIGHT, 0.4))
	_shape(body, "South", Vector3(0, WALL_HEIGHT * 0.5, d * 0.5 + 0.0), Vector3(w, WALL_HEIGHT, 0.4))
	_shape(body, "West", Vector3(-w * 0.5 + 0.1, WALL_HEIGHT * 0.5, 0), Vector3(0.4, WALL_HEIGHT, d))
	_shape(body, "East", Vector3(w * 0.5 + 0.0, WALL_HEIGHT * 0.5, 0), Vector3(0.4, WALL_HEIGHT, d))
	# Exit door and entry spawn.
	var door := _instance(KIT + "Door_1_Round.gltf", walls)
	door.name = "ExitDoor"
	door.position = Vector3(door_x - 0.52, 0.0, -d * 0.5 + 0.12)
	var exit := Node3D.new()
	exit.name = "Exit"
	exit.position = Vector3(door_x, 0.0, -d * 0.5 + 0.7)
	_add(exit)
	var area := _interactable(exit, 0.9)
	room.exit_interactable = room.get_path_to(area)
	var rug := _box("DoorRug", Vector3(door_x, 0.012, -d * 0.5 + 1.3), Vector3(1.4, 0.02, 1.0), Color(0.55, 0.22, 0.2), false)
	rug.name = "DoorRug"
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	_add(spawns)
	var entry := Marker3D.new()
	entry.name = "Entry"
	entry.position = Vector3(door_x, 0.05, -d * 0.5 + 1.6)
	spawns.add_child(entry)
	entry.owner = room


## Glazes a window wall piece: the MegaKit frame, and a pale daylight panel just outside
## the hole (instead of the dark void around the room).
func _window(piece: Node3D) -> void:
	var frame := _instance(KIT + "Window_Wide_Round1.gltf", piece)
	frame.position = Vector3.ZERO
	var sky := MeshInstance3D.new()
	sky.name = "Daylight"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.7)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.78, 0.88, 1.0)
	quad.material = material
	sky.mesh = quad
	sky.position = Vector3(0, 1.88, -0.36)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_child(sky)
	sky.owner = room


func _environment(ambient: Color, energy: float) -> void:
	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.045, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.ssao_enabled = true
	node.environment = env
	_add(node)
	var sun := DirectionalLight3D.new()
	sun.name = "WindowLight"
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -35, 0)
	_add(sun)


func _light(at: Vector3, color: Color, energy: float, range: float) -> void:
	var light := OmniLight3D.new()
	light.name = "RoomLight"
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range
	light.shadow_enabled = true
	_add(light)


func _prop(model: String, at: Vector3, yaw: float, solid: bool = false, half: Vector3 = Vector3.ZERO) -> Node3D:
	var props := room.get_node_or_null(^"Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		_add(props)
	var node := _instance(PROPS + model + ".gltf", props)
	node.position = at
	node.rotation_degrees = Vector3(0, yaw, 0)
	if solid:
		var body := StaticBody3D.new()
		body.name = model + "Collider"
		body.position = at
		body.rotation_degrees = Vector3(0, yaw, 0)
		props.add_child(body)
		body.owner = room
		_shape(body, "Shape", Vector3(0, half.y, 0), half * 2.0)
	return node


func _npc(scene: String, at: Vector3, yaw: float) -> Node3D:
	var holder := room.get_node_or_null(^"NPCs") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "NPCs"
		_add(holder)
	var npc := (load(NPCS + scene + ".tscn") as PackedScene).instantiate() as Node3D
	npc.position = at
	npc.rotation_degrees = Vector3(0, yaw, 0)
	holder.add_child(npc)
	npc.owner = room
	return npc


func _box(node_name: String, at: Vector3, size: Vector3, color: Color, solid: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	box.material = material
	mesh.mesh = box
	mesh.position = at
	_add(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.name = node_name + "Collider"
		body.position = at
		_add(body)
		_shape(body, "Shape", Vector3.ZERO, size)
	return mesh


func _shape(body: StaticBody3D, node_name: String, at: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	shape.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	shape.owner = room


func _interactable(parent: Node3D, radius: float) -> Area3D:
	var area := Area3D.new()
	area.name = "Interactable"
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	area.set_script(load("res://scripts/interaction/interactable.gd"))
	parent.add_child(area)
	area.owner = room
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	shape.position = Vector3(0, 0.6, 0)
	area.add_child(shape)
	shape.owner = room
	return area


func _instance(path: String, parent: Node) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.name = path.get_file().get_basename()
	parent.add_child(node, true)
	node.owner = room
	return node


func _add(node: Node) -> void:
	room.add_child(node, true)
	node.owner = room


func _save(file: String) -> void:
	var packed := PackedScene.new()
	var error := packed.pack(room)
	if error == OK:
		error = ResourceSaver.save(packed, OUT + file + ".tscn")
	print("%s: %s" % [file, error_string(error)])
	room.free()
