extends SceneTree
## Phase 8: builds res://scenes/locations/food_market.tscn, Willowmere's Food Market stall:
## a striped-awning counter dressed with Food & Market models (Avramania, CC0, vendored in
## assets/models/food_market/), Grocer Tilda behind it, a hanging sign and a WorldLocation.
## Like the Toolwright's stall it has no shop logic of its own: the root uses ToolStall
## (group "shop_locations"), so ShopUI gives Tilda a Merchant selling data/shops/
## food_market.tres at runtime. Change this generator, not the scene, then re-run:
##   godot --headless --path . --script res://tools/generate_food_market.gd

const OUT := "res://scenes/locations/food_market.tscn"
const FOOD := "res://assets/models/food_market/mdvl_food_%s.glb"
const MATERIALS := "res://assets/materials/buildings/"
const STALL := preload("res://scripts/world/tool_stall.gd")
const WORLD_LOCATION := preload("res://scripts/world/world_location.gd")
const NPC_SCENE := "res://scenes/npc/characters/grocer_tilda.tscn"
## The Food & Market models are life-size; goods are shown a little larger so they read
## from the iso camera.
const GOODS_SCALE := 1.7

var root_node: Node3D
var _cache := {}
var _mats := {}


func _initialize() -> void:
	root_node = Node3D.new()
	root_node.name = "FoodMarket"
	root_node.set_script(STALL)
	root_node.set(&"catalog", load("res://data/shops/food_market.tres"))
	# Faces +Z: counter in front, Tilda behind it, the awning over both.
	var counter := StaticBody3D.new()
	_add(root_node, counter, "Counter", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.6)))
	_mat_box("Top", Vector3(2.8, 0.08, 0.72), Vector3(0, 0.96, 0), "timber", counter)
	_mat_box("Front", Vector3(2.76, 0.92, 0.06), Vector3(0, 0.46, 0.33), "planks", counter)
	_mat_box("SideL", Vector3(0.06, 0.92, 0.68), Vector3(-1.37, 0.46, 0), "planks", counter)
	_mat_box("SideR", Vector3(0.06, 0.92, 0.68), Vector3(1.37, 0.46, 0), "planks", counter)
	_collider(counter, _box_shape(Vector3(2.8, 1.0, 0.72)), Vector3(0, 0.5, 0))
	var top := 1.0
	# Produce crate full of vegetables, cheese, bread, potions and ale on the counter.
	var crate := _food("produce_crate_01", counter, "ProduceCrate", Vector3(-0.85, top, 0.02), 10.0)
	for spec: Array in [["cabbage_01", Vector3(-0.14, 0.06, 0.0)], ["carrot_01", Vector3(0.12, 0.05, 0.05)], ["onion_01", Vector3(0.18, 0.05, -0.06)], ["onion_01", Vector3(0.05, 0.05, -0.08)]]:
		_food(spec[0], crate, String(spec[0]).to_pascal_case(), spec[1], 0.0, 1.0)
	_food("cheese_wheel_01", counter, "CheeseWheel", Vector3(-0.2, top, -0.08), -20.0)
	var plate := _food("plate_01", counter, "Plate", Vector3(0.28, top, 0.12), 0.0)
	_food("loaf_01", plate, "Loaf", Vector3(0, 0.02, 0), 30.0, 1.0)
	_food("roll_01", counter, "Roll", Vector3(0.5, top, 0.2), 0.0)
	for i in 3:
		_food("potion_01", counter, "Potion%d" % i, Vector3(0.72 + i * 0.13, top, -0.12 + (i % 2) * 0.08), i * 25.0)
	_food("ale_mug_01", counter, "AleMug", Vector3(1.12, top, 0.18), -60.0)
	_food("apple_01", counter, "Apple1", Vector3(0.02, top, 0.22), 0.0)
	_food("apple_01", counter, "Apple2", Vector3(0.1, top, 0.26), 90.0)
	_food("grapes_01", counter, "Grapes", Vector3(-0.42, top, 0.22), 40.0)
	# Awning: four posts, a front beam and a striped cloth roof.
	var awning := _group(root_node, "Awning")
	for post_x: float in [-1.5, 1.5]:
		for post_z: float in [-1.0, 1.15]:
			var tall := post_z < 0.0
			_mat_box("Post", Vector3(0.1, 2.6 if tall else 2.25, 0.1), Vector3(post_x, 1.3 if tall else 1.125, post_z), "timber", awning)
	_mat_box("FrontBeam", Vector3(3.1, 0.1, 0.1), Vector3(0, 2.2, 1.15), "timber", awning)
	var cloth := _group(awning, "Cloth")
	cloth.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(9)), Vector3(0, 2.43, 0.07))
	for i in 7:
		var stripe := _box("Stripe%d" % i, Vector3(3.3 / 7.0, 0.05, 2.5), Color(0.78, 0.2, 0.16) if i % 2 == 0 else Color(0.95, 0.9, 0.78), cloth)
		stripe.position = Vector3(-1.65 + 3.3 / 7.0 * (i + 0.5), 0, 0)
	# Scalloped valance along the front edge.
	for i in 7:
		var flap := _box("Flap%d" % i, Vector3(3.3 / 7.0 - 0.02, 0.22, 0.03), Color(0.78, 0.2, 0.16) if i % 2 == 0 else Color(0.95, 0.9, 0.78), awning)
		flap.position = Vector3(-1.65 + 3.3 / 7.0 * (i + 0.5), 2.14, 1.3)
	# Herbs and a ham hanging from the beam.
	_food("herb_bundle_01", awning, "Herbs", Vector3(-1.0, 1.72, 1.12), 0.0, 1.2)
	_food("ham_01", awning, "HangingHam", Vector3(0.9, 1.78, 1.1), 90.0, 1.3).rotation_degrees.x = 80.0
	# Sign over the stall.
	var sign_board := _mat_box("SignBoard", Vector3(1.6, 0.42, 0.06), Vector3(0, 2.72, 1.22), "planks", awning)
	sign_board.rotation_degrees.x = -12.0
	var text := Label3D.new()
	text.text = "Food Market"
	text.font_size = 64
	text.pixel_size = 0.0042
	text.outline_size = 10
	text.modulate = Color(1.0, 0.92, 0.7)
	text.outline_modulate = Color(0.25, 0.12, 0.05)
	_add(sign_board, text, "Text", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.04)))
	# Stock round the stall: a cask, grain sacks, a crate of apples, scales.
	var cask := StaticBody3D.new()
	_add(root_node, cask, "Cask", Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.05, 0, 0.75)))
	_food("cask_01", cask, "Model", Vector3.ZERO, 0.0, 1.5)
	_collider(cask, _cylinder_shape(0.35, 0.7), Vector3(0, 0.35, 0))
	var sacks := StaticBody3D.new()
	_add(root_node, sacks, "GrainSacks", Transform3D(Basis.IDENTITY, Vector3(2.05, 0, 0.5)))
	_food("grain_sack_01", sacks, "Sack1", Vector3(0, 0, 0), 20.0, 1.4)
	_food("grain_sack_01", sacks, "Sack2", Vector3(0.1, 0, 0.55), -35.0, 1.3)
	_collider(sacks, _box_shape(Vector3(0.7, 0.8, 1.2)), Vector3(0.05, 0.4, 0.28))
	var ground_crate := _food("produce_crate_01", root_node, "AppleCrate", Vector3(-2.0, 0, 1.6), 15.0, 1.6)
	for i in 6:
		_food("apple_01", ground_crate, "Apple%d" % i, Vector3(-0.15 + (i % 3) * 0.14, 0.06, -0.06 + (i / 3) * 0.12), i * 40.0, 1.0)
	_food("scales_01", root_node, "Scales", Vector3(2.1, 0, 1.5), -30.0, 1.4)
	var merchant := (load(NPC_SCENE) as PackedScene).instantiate() as Node3D
	# NPCs face their local -Z; turned round so Tilda faces her customers over the counter.
	_add(root_node, merchant, "Merchant", Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.3)))
	root_node.set(&"merchant", merchant)
	var markers := _group(root_node, "Markers")
	_add(markers, Marker3D.new(), "ShopFront", Transform3D(Basis.IDENTITY, Vector3(0, 0, 1.9)))
	var location := Marker3D.new()
	location.set_script(WORLD_LOCATION)
	_add(root_node, location, "Location", Transform3D.IDENTITY)
	location.set(&"location_id", &"food_market")
	location.set(&"display_name", "Willowmere Food Market")
	location.set(&"subtitle", "Grocer Tilda")
	location.set(&"kind", WorldLocation.Kind.SHOP)
	location.set(&"discover_radius", 7.0)
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("%s err=%d" % [OUT, err])
	root_node.free()
	quit()


## A Food & Market model under parent at local position, turned yaw degrees.
func _food(model: String, parent: Node, node_name: String, at: Vector3, yaw: float, size: float = GOODS_SCALE) -> Node3D:
	var path := FOOD % model
	if not _cache.has(path):
		_cache[path] = load(path)
	var node := (_cache[path] as PackedScene).instantiate() as Node3D
	_add(parent, node, node_name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)).scaled(Vector3.ONE * size), at))
	return node


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


func _box(node_name: String, size: Vector3, color: Color, parent: Node) -> MeshInstance3D:
	var key := str(color)
	if not _mats.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		_mats[key] = material
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mats[key]
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
