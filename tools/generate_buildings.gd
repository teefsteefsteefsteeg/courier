extends SceneTree
## Phase 5F: assembles the village buildings from Medieval Village MegaKit pieces
## and writes one scene per building to res://scenes/buildings/. Each scene keeps
## the collider of the Phase 5A building it replaces (same box, same place), so
## the Phase 5E layout, roads, NPC routes and quest markers are untouched.
##   godot --headless --path . --script res://tools/generate_buildings.gd
##
## Kit units: one wall module is 2 m wide and a storey is 3 m tall; the `Model`
## node scales the kit down (0.8 for houses) to fit the old footprints.
## A building faces +Z (its door side); the isometric camera sees +Z and +X.

const KIT := "res://assets/models/megakit/buildings/"
const MATERIALS := "res://assets/materials/buildings/"
const OUT := "res://scenes/buildings/"
const STOREY := 3.0
## Collider boxes of the Phase 5A scenes (scenes/props/medieval/*), centred at y = 1.6.
const BOX_HOUSE_1 := Vector3(3.852, 3.2, 4.788)
const BOX_HOUSE_2 := Vector3(3.197, 3.2, 4.925)
const BOX_ALCHEMY := Vector3(3.0965, 3.2, 4.77)
const BOX_INN := Vector3(4.896, 3.2, 4.884)
const BOX_BLACKSMITH := Vector3(5.602, 3.2, 4.723)
const BOX_MILL := Vector3(3.305, 3.2, 4.423)
## The Phase 5B bell tower's collider (scenes/props/env/bell_tower.tscn), centred at y = 1.5.
const BOX_BELL_TOWER := Vector3(3.1125, 3.0, 3.5811)
const BELL := "res://assets/models/quaternius/medieval_village/Bell.fbx"
## New in Phase 5F: the armory hall (scenes/locations/armory.tscn), walls plus 0.1 m.
const BOX_ARMORY := Vector3(5.0, 3.2, 3.4)

## Wall letters -> piece suffix. Upper case = with a door or window fill.
const WALLS := {
	"S": "Straight", "G": "WoodGrid", "B": "Straight_Base", "D": "Door_Round", "d": "Door_Flat",
	"W": "Window_Wide_Round", "F": "Window_Wide_Flat", "w": "Window_Thin_Round",
}
const FILLS := {
	"D": ["Door_1_Round"], "d": ["Door_8_Flat"], "W": ["Window_Wide_Round1"], "F": ["Window_Wide_Flat1"],
	"w": ["Window_Thin_Round1"],
}
const SHUTTERS := {"W": "WindowShutters_Wide_Round_Open", "F": "WindowShutters_Wide_Flat_Open",
		"w": "WindowShutters_Thin_Round_Open"}

var building: MedievalBuilding
var model: Node3D
var _scenes := {}
var _materials := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for spec in [
		["rose_cottage", BOX_HOUSE_1, _rose_cottage],
		["oak_house", BOX_HOUSE_2, _oak_house],
		["fern_cottage", BOX_HOUSE_1, _fern_cottage],
		["blue_house", BOX_HOUSE_2, _blue_house],
		["brook_cottage", BOX_HOUSE_2, _brook_cottage],
		["moss_cottage", BOX_HOUSE_1, _moss_cottage],
		["inn", BOX_INN, _inn],
		["blacksmith", BOX_BLACKSMITH, _blacksmith],
		["mill", BOX_MILL, _mill],
		["alchemy_shop", BOX_ALCHEMY, _alchemy_shop],
		["bell_tower", BOX_BELL_TOWER, _bell_tower],
		["armory_hall", BOX_ARMORY, _armory_hall],
	]:
		_begin(spec[0], spec[1])
		(spec[2] as Callable).call()
		_save(spec[0])
	quit()


# --- buildings ----------------------------------------------------------------

## One-storey plaster cottage: round door beside a shuttered window, a dormer
## on the sunny side, chimney at the back.
func _rose_cottage() -> void:
	building.roof_color = Color(0.78, 0.3, 0.28)
	_storey(2, 3, 0, "plaster", {"front": "DW", "right": "WGW", "left": "SwS", "back": "wS"}, true)
	_gable_roof(2, 3, 1)
	_dormer(2, 3, 1, 1, 0.0)
	_piece("Prop_Chimney", Vector3(-1.1, STOREY + 0.3, -1.8))


## Two storeys: stone ground floor, timber-framed upper floor with a front balcony.
func _oak_house() -> void:
	building.roof_color = Color(0.86, 0.52, 0.22)
	_storey(2, 3, 0, "brick", {"front": "dF", "right": "FSF", "left": "FwF", "back": "wF"})
	_storey(2, 3, 1, "plaster", {"front": "WW", "right": "GwG", "left": "wGw", "back": "Ww"}, true)
	_balcony_front(2, 3, 1)
	_gable_roof(2, 3, 2)
	_piece("Prop_Chimney2", Vector3(1.2, 2 * STOREY + 0.3, -1.6))


## Timber-grid cottage with a wooden porch over the door and a dormer each side.
func _fern_cottage() -> void:
	building.roof_color = Color(0.32, 0.58, 0.34)
	_storey(2, 3, 0, "plaster", {"front": "wD", "right": "GwG", "left": "wGw", "back": "wG"}, true, "Corner_Exterior_Wood", "WindowShutters_Thin_Round_Closed")
	_gable_roof(2, 3, 1)
	_dormer(2, 3, 1, 1, 1.2)
	_dormer(2, 3, 1, -1, -1.2)
	_porch(Vector3(1, 0, 3))
	_piece("Prop_Chimney2", Vector3(-1.2, STOREY + 0.3, -1.8))


## Tall stone-and-plaster townhouse with arched windows and a side balcony.
func _blue_house() -> void:
	building.roof_color = Color(0.28, 0.44, 0.78)
	_storey(2, 3, 0, "brick", {"front": "Dw", "right": "wSw", "left": "SwS", "back": "SS"})
	_storey(2, 3, 1, "plaster", {"front": "ww", "right": "wDw", "left": "wSw", "back": "SS"})
	_balcony_side(2, 3, 1)
	_gable_roof(2, 3, 2)
	_piece("Prop_Chimney", Vector3(-1.1, 2 * STOREY + 0.3, -1.8))


## Low stone cottage with wide shuttered windows and a thatch-coloured roof.
func _brook_cottage() -> void:
	building.roof_color = Color(0.8, 0.64, 0.24)
	_storey(2, 3, 0, "brick", {"front": "Fd", "right": "FSF", "left": "FwF", "back": "SF"}, true)
	_gable_roof(2, 3, 1)
	_piece("Prop_Chimney2", Vector3(1.2, STOREY + 0.3, 1.2))


## Plaster-on-stone cottage with a long roof and two dormers on the lane side.
func _moss_cottage() -> void:
	building.roof_color = Color(0.34, 0.56, 0.48)
	_storey(2, 3, 0, "base", {"front": "WD", "right": "BwB", "left": "WwW", "back": "Bw"}, true)
	_gable_roof(2, 3, 1)
	_dormer(2, 3, 1, -1, 1.2)
	_dormer(2, 3, 1, 1, -0.8)
	_piece("Prop_Chimney", Vector3(1.1, STOREY + 0.3, -1.8))


## The Willow inn: wide two-storey hall, stone below, timber above with a
## balcony along the front, dormers and two chimneys.
func _inn() -> void:
	building.roof_color = Color(0.7, 0.3, 0.22)
	_storey(3, 3, 0, "brick", {"front": "WDW", "right": "WSW", "left": "WSW", "back": "SdS"})
	_storey(3, 3, 1, "plaster", {"front": "wGw", "right": "GwG", "left": "GwG", "back": "GGG"}, true)
	_balcony_front(3, 3, 1)
	_gable_roof(3, 3, 2)
	_dormer(3, 3, 2, 1, 0.0)
	_dormer(3, 3, 2, -1, 0.0)
	_piece("Prop_Chimney", Vector3(-2.0, 2 * STOREY + 0.3, -2.0))
	_piece("Prop_Chimney", Vector3(2.0, 2 * STOREY + 0.3, -2.0))


## Stone forge: long hall turned side-on to the lane, an open timber canopy over
## the anvil, and a big chimney glowing at the hearth.
func _blacksmith() -> void:
	model.scale = Vector3.ONE * 0.93
	building.roof_color = Color(0.62, 0.24, 0.2)
	_storey(3, 2, 0, "brick", {"front": "FdF", "right": "SS", "left": "wS", "back": "SSS"})
	_gable_roof(3, 2, 1, true)
	for x in [-2.0, 0.0, 2.0]:
		_piece("Roof_Wooden_2x1", Vector3(x, 2.15, 2.0))
	for x in [-2.9, 2.9]:
		_piece("Prop_Support", Vector3(x, 0.0, 2.0))
	_piece("Prop_Chimney", Vector3(2.4, STOREY + 0.3, -0.6))
	# Hearth under the canopy: stone base, glowing coals, anvil on a stump.
	_box("Hearth", Vector3(1.2, 0.7, 0.8), Vector3(2.2, 0.35, 2.55), "stone")
	_box("Coals", Vector3(0.9, 0.08, 0.5), Vector3(2.2, 0.72, 2.55), "embers")
	_cylinder("Stump", 0.32, 0.55, Vector3(-1.0, 0.275, 2.6), "planks")
	_box("Anvil", Vector3(0.7, 0.28, 0.3), Vector3(-1.0, 0.69, 2.6), "iron")


## Stone tower mill with a timber cap storey and turning sails over the door.
func _mill() -> void:
	building.roof_color = Color(0.55, 0.36, 0.24)
	_storey(2, 2, 0, "brick", {"front": "DS", "right": "Sw", "left": "wS", "back": "SS"})
	_storey(2, 2, 1, "brick", {"front": "Sw", "right": "wS", "left": "Sw", "back": "SS"})
	_storey(2, 2, 2, "plaster", {"front": "GG", "right": "GG", "left": "GG", "back": "GG"})
	_gable_roof(2, 2, 3)
	_sails(Vector3(0, 2.4 * STOREY, 2.55))


## Purple-roofed alchemist's tower with a low shopfront, glowing violet windows.
func _alchemy_shop() -> void:
	building.roof_color = Color(0.48, 0.26, 0.68)
	building.wall_color = Color(0.86, 0.8, 0.94)
	building.window_glow = Color(0.75, 0.45, 1)
	building.window_glow_energy = 1.4
	var tower := Vector3(0, 0, -1)
	_storey(2, 2, 0, "brick", {"right": "Sw", "left": "wS", "back": "SS"}, false, "Corner_Exterior_Brick", "", tower)
	_storey(2, 2, 1, "plaster", {"front": "SS", "right": "Gw", "left": "wG", "back": "GG"}, false, "Corner_Exterior_Wood", "", tower)
	_storey(2, 2, 2, "plaster", {"front": "WW", "right": "wW", "left": "Ww", "back": "ww"}, false, "Corner_Exterior_Wood", "", tower)
	_piece("Roof_Tower_RoundTiles", tower + Vector3(0, 3 * STOREY, 0))
	# Shopfront: one module deep in front of the tower.
	var shop := Vector3(0, 0, 2)
	_wall("brick", "W", shop + Vector3(-1, 0, 1), 0.0, true)
	_wall("brick", "D", shop + Vector3(1, 0, 1), 0.0, false)
	_wall("brick", "w", shop + Vector3(2, 0, 0), 90.0, false)
	_wall("brick", "w", shop + Vector3(-2, 0, 0), -90.0, false)
	for corner in [Vector3(-2, 0, 3), Vector3(2, 0, 3)]:
		_piece("Corner_Exterior_Brick", corner, 0.0 if corner.x < 0 else 90.0)
	# Gabled shop roof; its back half runs into the tower.
	_piece("Roof_RoundTiles_4x4", Vector3(0, STOREY, 1.0))
	_piece("Roof_Front_Brick4", Vector3(0, STOREY, 3.0))


## Plaza bell tower: stone shaft, an open belfry of timber arches, spire roof.
func _bell_tower() -> void:
	model.scale = Vector3.ONE * 0.78
	building.roof_color = Color(0.75, 0.32, 0.22)
	(building.get_node(^"CollisionShape3D") as CollisionShape3D).position.y = 1.5
	_storey(2, 2, 0, "brick", {"front": "dS", "right": "Sw", "left": "wS", "back": "SS"})
	_storey(2, 2, 1, "brick", {"front": "wS", "right": "Sw", "left": "wS", "back": "Sw"})
	var y := 2 * STOREY
	for face in ["front", "back", "right", "left"]:
		for i in 2:
			var slot := _slot(face, 2, 2, i)
			_piece("Wall_Arch", Vector3(slot.x, y, slot.y), slot.z)
	for c in [Vector3(-2, y, 2), Vector3(2, y, 2), Vector3(2, y, -2), Vector3(-2, y, -2)]:
		_piece("Corner_Exterior_Wood", c)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_piece("Floor_WoodDark", Vector3(x, y + 0.02, z))
	var bell := (load(BELL) as PackedScene).instantiate() as Node3D
	bell.position = Vector3(0, y + 0.4, 0)
	bell.scale = Vector3.ONE * 1.6
	model.add_child(bell, true)
	bell.owner = building
	_piece("Roof_Tower_RoundTiles", Vector3(0, 3 * STOREY, 0))


## Armory hall: stone ground floor with the shop door, timber upper floor with
## a balcony for the shields and sign, side-on slate roof whose gable (with the
## shop's emblem, see scenes/locations/armory.tscn) faces the camera.
func _armory_hall() -> void:
	building.roof_color = Color(0.36, 0.42, 0.52)
	_storey(3, 2, 0, "brick", {"front": "WDW", "right": "Sw", "left": "wS", "back": "SSS"}, true)
	_storey(3, 2, 1, "plaster", {"front": "wGw", "right": "Gw", "left": "wG", "back": "GGG"})
	_balcony_front(3, 2, 1)
	_gable_roof(3, 2, 2, true)
	_piece("Prop_Chimney", Vector3(-2.0, 2 * STOREY + 0.3, -0.8))


# --- building blocks ---------------------------------------------------------

## One storey of a box `hw` x `hd` modules (half extents in metres = module
## count). `faces` lists each face's modules left to right as seen from outside.
func _storey(hw: int, hd: int, level: int, style: String, faces: Dictionary, shutters := false,
		corner := "", shutter_piece := "", offset := Vector3.ZERO) -> void:
	var y := level * STOREY
	for face in faces:
		var layout: String = faces[face]
		for i in layout.length():
			var slot := _slot(face, hw, hd, i)
			_wall(style, layout[i], offset + Vector3(slot.x, y, slot.y), slot.z, shutters, shutter_piece)
	if corner.is_empty():
		# Stone quoins (3k triangles each) only on the ground floor; timber posts above.
		corner = "Corner_Exterior_Brick" if style == "brick" and level == 0 else "Corner_Exterior_Wood"
	var corners := [[Vector3(-hw, y, hd), 0.0], [Vector3(hw, y, hd), 90.0], [Vector3(hw, y, -hd), 180.0], [Vector3(-hw, y, -hd), 270.0]]
	for c in corners:
		_piece(corner, offset + c[0], c[1] if corner == "Corner_Exterior_Brick" else 0.0)


## (x, z, yaw) of module `i` on a face.
func _slot(face: String, hw: int, hd: int, i: int) -> Vector3:
	match face:
		"front":
			return Vector3(-hw + 1 + 2 * i, hd, 0.0)
		"back":
			return Vector3(hw - 1 - 2 * i, -hd, 180.0)
		"right":
			return Vector3(hw, hd - 1 - 2 * i, 90.0)
		_:
			return Vector3(-hw, -hd + 1 + 2 * i, 270.0)


func _wall(style: String, letter: String, pos: Vector3, yaw: float, shutters := false, shutter_piece := "") -> void:
	var family: String = {"plaster": "Wall_Plaster_", "base": "Wall_Plaster_", "brick": "Wall_UnevenBrick_"}[style]
	var suffix: String = WALLS[letter]
	if style == "brick" and letter in ["G", "B"]:
		suffix = "Straight"
	if style == "base" and letter == "S":
		suffix = "Straight_Base"
	_piece(family + suffix, pos, yaw)
	for fill in FILLS.get(letter, []):
		var at := pos
		if fill.begins_with("Door"):
			at += Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(-0.53, 0, 0)
		_piece(fill, at, yaw)
	if shutters and SHUTTERS.has(letter):
		_piece(shutter_piece if not shutter_piece.is_empty() else SHUTTERS[letter], pos, yaw)


## Tile roof on a box, ridge along Z (or along X when `side_on`), with gable ends.
func _gable_roof(hw: int, hd: int, levels: int, side_on := false) -> void:
	var y := levels * STOREY
	var across := hd if side_on else hw
	var along := hw if side_on else hd
	var yaw := 90.0 if side_on else 0.0
	_piece("Roof_RoundTiles_%dx%d" % [across * 2, along * 2], Vector3(0, y, 0), yaw)
	var front := "Roof_Front_Brick%d" % (across * 2)
	if side_on:
		_piece(front, Vector3(hw, y, 0), 90.0)
		_piece(front, Vector3(-hw, y, 0), 270.0)
	else:
		_piece(front, Vector3(0, y, hd), 0.0)
		_piece(front, Vector3(0, y, -hd), 180.0)


## Dormer window on the roof slope facing +X (`side` 1) or -X (`side` -1).
func _dormer(hw: int, hd: int, levels: int, side: int, z: float) -> void:
	_piece("Roof_Dormer_RoundTile", Vector3(side * hw * 0.3, levels * STOREY + 0.5, z), 0.0 if side > 0 else 180.0)


## Balcony one module deep along the front, on brackets from the storey below.
func _balcony_front(hw: int, hd: int, level: int) -> void:
	var y := level * STOREY
	for i in hw:
		var x := -hw + 1 + 2 * i
		_piece("Balcony_Cross_Straight", Vector3(x, y, hd + 1.0))
		_piece("Floor_WoodDark", Vector3(x, y, hd + 1.0))
	for x in range(-hw, hw + 1, 2):
		_piece("Prop_Support", Vector3(clampf(x, -hw + 0.15, hw - 0.15), y - STOREY, hd))


## Balcony one module wide on the +X side.
func _balcony_side(hw: int, hd: int, level: int) -> void:
	var y := level * STOREY
	_piece("Balcony_Simple_Straight", Vector3(hw + 1.0, y, 0), 90.0)
	_piece("Floor_WoodDark", Vector3(hw + 1.0, y, 0))
	for z in [-0.85, 0.85]:
		_piece("Prop_Support", Vector3(hw, y - STOREY, z), 90.0)


## Wooden canopy over a doorway, held up by wall brackets.
func _porch(at: Vector3) -> void:
	_piece("Roof_Wooden_2x1", at + Vector3(0, 2.15, 0))
	for x in [-0.9, 0.9]:
		_piece("Prop_Support", at + Vector3(x, 0, 0))


## Four lattice sails on a hub, under a separate turning node.
func _sails(hub: Vector3) -> void:
	var sails := Spinner.new()
	sails.name = "Sails"
	sails.position = hub * model.scale
	sails.scale = model.scale
	building.add_child(sails)
	sails.owner = building
	var holder := model
	model = sails
	_cylinder("Hub", 0.35, 0.5, Vector3(0, 0, 0.1), "planks", Vector3(90, 0, 0))
	for i in 4:
		var arm := Node3D.new()
		arm.name = "Arm%d" % i
		arm.rotation_degrees = Vector3(0, 0, i * 90.0 + 15.0)
		sails.add_child(arm)
		arm.owner = building
		model = arm
		_box("Spar", Vector3(0.18, 4.6, 0.14), Vector3(0, 2.4, 0.3), "planks")
		_box("Cloth", Vector3(1.1, 3.4, 0.05), Vector3(0.62, 2.8, 0.32), "plaster")
		for j in 5:
			_box("Lath%d" % j, Vector3(1.25, 0.08, 0.08), Vector3(0.62, 1.2 + j * 0.8, 0.38), "planks")
		_box("Edge", Vector3(0.08, 3.5, 0.08), Vector3(1.22, 2.8, 0.38), "planks")
		model = sails
	model = holder


# --- scene plumbing ----------------------------------------------------------

func _begin(scene_name: String, box: Vector3) -> void:
	building = MedievalBuilding.new()
	building.name = scene_name.to_pascal_case()
	building.merge_model = true
	building.window_glow = Color(1, 0.8, 0.45)
	model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * 0.8
	building.add_child(model)
	model.owner = building
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.position = Vector3(0, 1.6, 0)
	var box_shape := BoxShape3D.new()
	box_shape.size = box
	shape.shape = box_shape
	building.add_child(shape)
	shape.owner = building


func _save(scene_name: String) -> void:
	var bounds := _bounds(model)
	var occluder := CameraOccluder.new()
	occluder.name = "CameraOccluder"
	var box := ((building.get_node(^"CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size
	occluder.radius = snappedf(0.5 * Vector2(box.x, box.z).length(), 0.01)
	occluder.height = snappedf(bounds.end.y, 0.01)
	building.add_child(occluder)
	occluder.owner = building
	var packed := PackedScene.new()
	var err := packed.pack(building)
	if err == OK:
		err = ResourceSaver.save(packed, OUT + scene_name + ".tscn")
	print("%s: %d pieces, %s x %s m, top %.2f m, err=%d" % [scene_name, model.get_child_count(),
			snappedf(bounds.size.x, 0.01), snappedf(bounds.size.z, 0.01), bounds.end.y, err])
	building.free()


func _piece(piece: String, pos: Vector3, yaw := 0.0) -> Node3D:
	if not _scenes.has(piece):
		_scenes[piece] = load(KIT + piece + ".gltf")
	var node := (_scenes[piece] as PackedScene).instantiate() as Node3D
	node.position = pos
	node.rotation_degrees.y = yaw
	model.add_child(node, true)
	node.owner = building
	return node


func _box(node_name: String, size: Vector3, pos: Vector3, material: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_primitive(node_name, mesh, pos, material, Vector3.ZERO)


func _cylinder(node_name: String, radius: float, height: float, pos: Vector3, material: String, rotation := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	_primitive(node_name, mesh, pos, material, rotation)


func _primitive(node_name: String, mesh: PrimitiveMesh, pos: Vector3, material: String, rotation: Vector3) -> void:
	if not _materials.has(material):
		_materials[material] = load(MATERIALS + material + ".tres")
	mesh.material = _materials[material]
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rotation
	model.add_child(node, true)
	node.owner = building


## Bounds of every mesh under the building root, in building space.
func _bounds(_from: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for child in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var local := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != building:
			local = (walk as Node3D).transform * local
			walk = walk.get_parent()
		var box := local * mesh.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
