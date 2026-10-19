extends SceneTree
## Phase 5F: builds Willowmere's armory from KayKit Fantasy Weapons Bits and the
## shared building materials. Writes the modular display props to
## res://scenes/props/armory/ and the composite location to
## res://scenes/locations/armory.tscn (run tools/generate_buildings.gd first for
## the hall itself).
##   godot --headless --path . --script res://tools/generate_armory.gd
##
## Location space: the hall is centred on the origin and faces +Z; its front
## wall is at z = 1.67 and the balcony above the counter reaches z = 3.2. The
## yard opens onto the forest road, so no extra path is needed.

const WEAPONS := "res://assets/models/kaykit_weapons/"
const MATERIALS := "res://assets/materials/buildings/"
const PROPS := "res://scenes/props/armory/"
const LOCATION := "res://scenes/locations/armory.tscn"
const HALL := "res://scenes/buildings/armory_hall.tscn"
const MERCHANT := "res://scenes/npc/characters/weaponsmith_brenna.tscn"
const BARREL := "res://assets/models/quaternius/medieval_village/Barrel.fbx"
const MERGED_PROP := preload("res://scripts/world/merged_prop.gd")
const ARMORY := preload("res://scripts/world/armory.gd")
## Display scale for the weapons (a sword is about 1 m long).
const SCALE := 0.55
## Lying flat on a table, blade along +X.
const FLAT := Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
## Where the barrel of swords stands (location space).
const BARREL_SPOT := Vector3(-2.95, 0, 1.0)

var root_node: Node3D
var model: Node3D
var _scenes := {}
var _materials := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(PROPS)
	_prop("polearm_rack", Vector3(1.7, 1.5, 0.45), _polearm_rack)
	_prop("sword_rack", Vector3(1.6, 1.0, 0.4), _sword_rack)
	_prop("display_table", Vector3(1.5, 0.82, 0.7), _display_table)
	_prop("merchant_counter", Vector3(1.8, 1.0, 0.6), _merchant_counter)
	_prop("weapon_barrel", Vector3(0.8, 1.0, 0.8), _weapon_barrel, true)
	_prop("armory_emblem", Vector3.ZERO, _emblem)
	_location()
	quit()


# --- display props (prop space: faces +Z, stands on y = 0) --------------------

## Spears, a halberd and staffs leaning back against a crossbar.
func _polearm_rack() -> void:
	_frame(1.7, 1.45, 0.45)
	_box("MidBar", Vector3(1.7, 0.06, 0.08), Vector3(0, 0.9, -0.12), "timber")
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-6))
	_weapon("spear_A", Vector3(-0.58, 0.12 + 1.03 * SCALE, 0.04), lean)
	_weapon("halberd", Vector3(-0.2, 0.12 + 0.93 * SCALE, 0.04), lean)
	_weapon("staff_B", Vector3(0.2, 0.12 + 0.86 * SCALE, 0.04), lean)
	_weapon("spear_A", Vector3(0.56, 0.12 + 1.03 * SCALE, 0.04), lean * Basis(Vector3.UP, deg_to_rad(90)))


## Five swords standing blade up.
func _sword_rack() -> void:
	_frame(1.6, 0.95, 0.4)
	_box("FrontBar", Vector3(1.6, 0.06, 0.06), Vector3(0, 0.32, 0.12), "timber")
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-5))
	var x := -0.6
	for sword in ["sword_A", "sword_B", "sword_C", "sword_D", "sword_E"]:
		_weapon(sword, Vector3(x, 0.1 + 0.43 * SCALE, 0.03), lean)
		x += 0.3


## Trestle table with axes, a hammer and daggers laid out, a shield leaning on it.
func _display_table() -> void:
	_trestle(1.5, 0.78, 0.7)
	var top := 0.815
	_weapon("axe_A", Vector3(-0.45, top + 0.13 * SCALE, -0.12), FLAT.rotated(Vector3.UP, deg_to_rad(8)))
	_weapon("hammer_A", Vector3(-0.3, top + 0.22 * SCALE, 0.16), FLAT.rotated(Vector3.UP, deg_to_rad(-12)))
	_weapon("dagger_A", Vector3(0.25, top + 0.08 * SCALE, -0.16), FLAT.rotated(Vector3.UP, deg_to_rad(4)))
	_weapon("dagger_B", Vector3(0.3, top + 0.05 * SCALE, 0.12), FLAT.rotated(Vector3.UP, deg_to_rad(176)))
	_weapon("axe_C", Vector3(0.62, top + 0.1 * SCALE, 0.0), FLAT.rotated(Vector3.UP, deg_to_rad(90)))
	_weapon("shield_A", Vector3(-0.35, 0.55 * SCALE, 0.42), Basis(Vector3.RIGHT, deg_to_rad(-14)))


## The merchant's counter: closed front, a bow, arrows, a wand and knuckle-dusters on top.
func _merchant_counter() -> void:
	_box("Top", Vector3(1.8, 0.08, 0.6), Vector3(0, 0.96, 0), "timber")
	_box("Front", Vector3(1.76, 0.92, 0.06), Vector3(0, 0.46, 0.26), "planks")
	_box("SideL", Vector3(0.06, 0.92, 0.56), Vector3(-0.85, 0.46, 0), "planks")
	_box("SideR", Vector3(0.06, 0.92, 0.56), Vector3(0.85, 0.46, 0), "planks")
	_box("Plinth", Vector3(1.84, 0.1, 0.64), Vector3(0, 0.05, 0.02), "timber")
	var top := 1.0
	_weapon("bow_A_withString", Vector3(-0.3, top + 0.03, 0.12), Basis.IDENTITY)
	_weapon("arrow_A", Vector3(0.35, top + 0.02, 0.0), Basis(Vector3.UP, deg_to_rad(80)))
	_weapon("arrow_B", Vector3(0.42, top + 0.02, -0.12), Basis(Vector3.UP, deg_to_rad(95)))
	_weapon("wand_A", Vector3(0.6, top + 0.06, 0.15), FLAT.rotated(Vector3.UP, deg_to_rad(30)))
	_weapon("fistweapon_A_stacked", Vector3(0.05, top, -0.15), Basis(Vector3.UP, deg_to_rad(20)))


## A barrel of swords (blade down), an axe and a mace.
func _weapon_barrel() -> void:
	var barrel := _instance(BARREL, Vector3.ZERO, Basis.IDENTITY.scaled(Vector3.ONE * 5.1387))
	barrel.name = "Barrel"
	var down := Basis(Vector3.BACK, PI)
	_weapon("sword_B", Vector3(-0.12, 1.15, 0.05), down.rotated(Vector3.BACK, deg_to_rad(10)))
	_weapon("sword_C", Vector3(0.1, 1.2, -0.08), down.rotated(Vector3.RIGHT, deg_to_rad(8)))
	_weapon("axe_B", Vector3(0.05, 0.75, 0.14), Basis(Vector3.BACK, deg_to_rad(-12)))
	_weapon("hammer_C", Vector3(-0.1, 0.7, -0.12), Basis(Vector3.RIGHT, deg_to_rad(-10)))


## Shop emblem for the gable: two crossed swords and a shield on a plank board.
func _emblem() -> void:
	_box("Board", Vector3(1.5, 1.1, 0.07), Vector3(0, 0, 0), "planks")
	_box("Rim", Vector3(1.6, 1.2, 0.04), Vector3(0, 0, -0.04), "timber")
	for angle in [-38.0, 38.0]:
		_weapon("sword_D", Vector3(0, -0.45, 0.08), Basis(Vector3.BACK, deg_to_rad(angle)), 0.7)
	_weapon("shield_B", Vector3(0, 0.02, 0.14), Basis.IDENTITY, 0.6)


# --- location -----------------------------------------------------------------

func _location() -> void:
	root_node = Node3D.new()
	root_node.name = "Armory"
	root_node.set_script(ARMORY)
	_add(root_node, (load(HALL) as PackedScene).instantiate(), "Hall", Transform3D.IDENTITY)
	var displays := _group("Displays")
	_add(displays, _load_prop("polearm_rack"), "PolearmRack", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2.78, 0, -0.2)))
	_add(displays, _load_prop("sword_rack"), "SwordRack", Transform3D(Basis.IDENTITY, Vector3(-1.45, 0, 2.0)))
	_add(displays, _load_prop("display_table"), "DisplayTable", Transform3D(Basis(Vector3.UP, deg_to_rad(6)), Vector3(-1.45, 0, 4.0)))
	_add(displays, _load_prop("merchant_counter"), "MerchantCounter", Transform3D(Basis.IDENTITY, Vector3(1.5, 0, 2.85)))
	# At the hall's west front corner, beside the sword rack: clear of the walk up to the
	# weaponsmith (ShopFront), the forest road and the plaza. It used to block the counter.
	_add(displays, _load_prop("weapon_barrel"), "WeaponBarrel", Transform3D(Basis.IDENTITY, BARREL_SPOT))
	# Shields and the sign on the balcony rail, the emblem on the gable that faces the camera.
	var facade := _group("Facade")
	_add(facade, _load_prop("armory_emblem"), "GableEmblem", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2.5, 5.75, 0)))
	model = facade
	for spec in [["shield_C", -1.7], ["shield_B", 1.7]]:
		_weapon(spec[0], Vector3(spec[1], 2.9, 3.32), Basis.IDENTITY, 0.6).name = "RailShield" + ("L" if spec[1] < 0 else "R")
	_box("SignBoard", Vector3(2.0, 0.5, 0.06), Vector3(0, 2.95, 3.3), "planks")
	var label := Label3D.new()
	label.name = "SignText"
	label.text = "ARMORY"
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 0
	label.modulate = Color(0.95, 0.82, 0.45)
	label.position = Vector3(0, 2.95, 3.34)
	_add(facade, label, "SignText", Transform3D(Basis.IDENTITY, label.position))
	# Weaponsmith behind the counter, facing the yard.
	var merchant := (load(MERCHANT) as PackedScene).instantiate() as Node3D
	# NPCs face their local -Z; turned round so the weaponsmith faces the yard over her counter.
	_add(root_node, merchant, "Merchant", Transform3D(Basis(Vector3.UP, PI), Vector3(1.5, 0, 2.05)))
	root_node.set("merchant", merchant)
	var markers := _group("Markers")
	for spec in [["MerchantSpot", Vector3(1.5, 0, 2.05)], ["ShopFront", Vector3(1.5, 0, 3.75)], ["Entrance", Vector3(0, 0, 2.0)]]:
		var marker := Marker3D.new()
		_add(markers, marker, spec[0], Transform3D(Basis.IDENTITY, spec[1]))
	_pack(root_node, LOCATION)


# --- helpers ------------------------------------------------------------------

func _prop(prop_name: String, box: Vector3, build: Callable, cylinder := false) -> void:
	root_node = StaticBody3D.new()
	root_node.name = prop_name.to_pascal_case()
	root_node.set_script(MERGED_PROP)
	model = Node3D.new()
	model.name = "Model"
	root_node.add_child(model)
	model.owner = root_node
	build.call()
	if box != Vector3.ZERO:
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.position = Vector3(0, box.y / 2, 0)
		if cylinder:
			var cyl := CylinderShape3D.new()
			cyl.radius = box.x / 2
			cyl.height = box.y
			shape.shape = cyl
		else:
			var box_shape := BoxShape3D.new()
			box_shape.size = box
			shape.shape = box_shape
		root_node.add_child(shape)
		shape.owner = root_node
	_pack(root_node, PROPS + prop_name + ".tscn")


func _load_prop(prop_name: String) -> Node3D:
	return (load(PROPS + prop_name + ".tscn") as PackedScene).instantiate() as Node3D


func _pack(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(node)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("%s err=%d" % [path, err])
	node.free()


func _group(group_name: String) -> Node3D:
	var node := Node3D.new()
	_add(root_node, node, group_name, Transform3D.IDENTITY)
	return node


func _add(parent: Node, node: Node, node_name: String, xform: Transform3D) -> void:
	node.name = node_name
	if node is Node3D:
		(node as Node3D).transform = xform
	parent.add_child(node)
	node.owner = root_node


## Frame for a rack: base, two uprights and a top bar, set back from the front.
func _frame(width: float, height: float, depth: float) -> void:
	_box("Base", Vector3(width, 0.12, depth), Vector3(0, 0.06, 0), "timber")
	for x in [-width / 2 + 0.05, width / 2 - 0.05]:
		_box("Upright", Vector3(0.1, height, 0.1), Vector3(x, height / 2, -0.12), "planks")
	_box("TopBar", Vector3(width, 0.08, 0.1), Vector3(0, height - 0.1, -0.12), "timber")


func _trestle(width: float, height: float, depth: float) -> void:
	_box("Top", Vector3(width, 0.07, depth), Vector3(0, height, 0), "planks")
	for x in [-width / 2 + 0.2, width / 2 - 0.2]:
		_box("Leg", Vector3(0.08, height, depth - 0.1), Vector3(x, height / 2, 0), "timber")
	_box("Stretcher", Vector3(width - 0.4, 0.06, 0.06), Vector3(0, 0.25, 0), "timber")


func _weapon(weapon: String, pos: Vector3, basis: Basis, scale := SCALE) -> Node3D:
	return _instance(WEAPONS + weapon + ".gltf", pos, basis.scaled(Vector3.ONE * scale))


func _instance(path: String, pos: Vector3, basis: Basis) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var node := (_scenes[path] as PackedScene).instantiate() as Node3D
	node.transform = Transform3D(basis, pos)
	model.add_child(node, true)
	node.owner = root_node
	return node


func _box(node_name: String, size: Vector3, pos: Vector3, material: String) -> MeshInstance3D:
	if not _materials.has(material):
		_materials[material] = load(MATERIALS + material + ".tres")
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _materials[material]
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	model.add_child(node, true)
	node.owner = root_node
	return node
