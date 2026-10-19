extends SceneTree
## Bakes the world map's terrain image from the real village: ground surfaces from the
## Phase 5E splat maps (grass, dirt lanes, cobbled roads, flagstone plazas, tilled fields,
## forest floor, clearing moss), trees as canopies, and every building, wall and large prop
## as its collider footprint. Writes res://assets/textures/map/world_map.png covering
## ExplorationService.WORLD_RECT at PIXELS_PER_METRE. Re-run after moving buildings or roads:
##   godot --headless --path . --script res://tools/bake_world_map.gd

const OUT := "res://assets/textures/map/world_map.png"
const SPLAT_A := "res://assets/textures/terrain/village_splat_a.png"
const SPLAT_B := "res://assets/textures/terrain/village_splat_b.png"
const SPLAT_ORIGIN := Vector2(-64.0, -64.0)
const SPLAT_SIZE := 128.0
const PIXELS_PER_METRE := 4

const GRASS := Color(0.47, 0.6, 0.33)
const GRASS_DRY := Color(0.6, 0.6, 0.38)
const DIRT := Color(0.71, 0.58, 0.4)
const COBBLE := Color(0.67, 0.64, 0.6)
const FLAG := Color(0.76, 0.7, 0.6)
const SOIL := Color(0.45, 0.33, 0.22)
const FOREST := Color(0.2, 0.3, 0.18)
const MOSS := Color(0.38, 0.55, 0.3)
const CANOPY := Color(0.16, 0.27, 0.15)
const CANOPY_EDGE := Color(0.1, 0.18, 0.1)
const ROOF := Color(0.55, 0.3, 0.22)
const ROOF_EDGE := Color(0.25, 0.13, 0.09)
const WALL := Color(0.62, 0.6, 0.57)
const PROP := Color(0.42, 0.33, 0.25)

var image: Image
var rect: Rect2
var size: Vector2i


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rect = ExplorationService.WORLD_RECT
	size = Vector2i(rect.size * PIXELS_PER_METRE)
	image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_paint_ground()
	var level := (load("res://scenes/levels/village.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for i in 30:
		await process_frame
	_paint_bodies(level)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := image.save_png(ProjectSettings.globalize_path(OUT))
	print("world map %s saved err=%d" % [size, err])
	quit()


func _paint_ground() -> void:
	var a := Image.load_from_file(ProjectSettings.globalize_path(SPLAT_A))
	var b := Image.load_from_file(ProjectSettings.globalize_path(SPLAT_B))
	a.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	b.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	for y in size.y:
		for x in size.x:
			var sa := a.get_pixel(x, y)
			var sb := b.get_pixel(x, y)
			var c := GRASS.lerp(GRASS_DRY, sb.b * 0.7)
			c = c.lerp(FOREST, sb.r)
			c = c.lerp(MOSS, sb.g)
			c = c.lerp(SOIL, sa.a)
			c = c.lerp(DIRT, sa.r)
			c = c.lerp(COBBLE, sa.g)
			c = c.lerp(FLAG, sa.b)
			# A little paper grain so flat areas read as a drawn map.
			var grain := (sin(x * 12.9898 + y * 78.233) * 43758.5453)
			grain = (grain - floorf(grain) - 0.5) * 0.035
			image.set_pixel(x, y, Color(c.r + grain, c.g + grain, c.b + grain, 1.0))


func _paint_bodies(level: Node) -> void:
	var trees := 0
	var buildings := 0
	for node in level.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var body := shape.get_parent()
		if not (body is StaticBody3D) or shape.shape == null or body.name in ["Ground", "Boundary"]:
			continue
		var path := String(level.get_path_to(body))
		var xform := shape.global_transform
		if shape.shape is CylinderShape3D or shape.shape is CapsuleShape3D:
			var radius := (shape.shape as CylinderShape3D).radius if shape.shape is CylinderShape3D else (shape.shape as CapsuleShape3D).radius
			if path.contains("Tree") or path.contains("tree"):
				_circle(Vector2(xform.origin.x, xform.origin.z), maxf(radius * 3.2, 1.4), CANOPY, CANOPY_EDGE)
				trees += 1
			elif radius >= 0.6:
				_circle(Vector2(xform.origin.x, xform.origin.z), radius, PROP, PROP.darkened(0.4))
		elif shape.shape is BoxShape3D:
			var box := (shape.shape as BoxShape3D).size
			var footprint := box.x * box.z
			var is_building := body is MedievalBuilding or path.begins_with("Buildings") or path.contains("Hall") or path.contains("BellTower")
			if is_building:
				_box(xform, box, ROOF, ROOF_EDGE)
				buildings += 1
			elif box.y >= 1.5 and (box.x >= 2.0 or box.z >= 2.0):
				_box(xform, box, WALL, WALL.darkened(0.35))
			elif footprint >= 0.6:
				_box(xform, box, PROP, PROP.darkened(0.4))
	print("painted %d trees, %d buildings" % [trees, buildings])


func _to_px(world: Vector2) -> Vector2:
	return (world - rect.position) * PIXELS_PER_METRE


func _circle(centre: Vector2, radius: float, fill: Color, edge: Color) -> void:
	var c := _to_px(centre)
	var r := radius * PIXELS_PER_METRE
	for y in range(maxi(floori(c.y - r - 1), 0), mini(ceili(c.y + r + 1), size.y)):
		for x in range(maxi(floori(c.x - r - 1), 0), mini(ceili(c.x + r + 1), size.x)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r:
				image.set_pixel(x, y, edge if d > r - 1.2 else fill)


## Filled, rotated rectangle for a box collider's footprint, with a 1 px darker edge.
func _box(xform: Transform3D, box: Vector3, fill: Color, edge: Color) -> void:
	var centre := Vector2(xform.origin.x, xform.origin.z)
	var ax := Vector2(xform.basis.x.x, xform.basis.x.z).normalized()
	var az := Vector2(xform.basis.z.x, xform.basis.z.z).normalized()
	var half := Vector2(box.x * 0.5 * Vector2(xform.basis.x.x, xform.basis.x.z).length(), box.z * 0.5 * Vector2(xform.basis.z.x, xform.basis.z.z).length())
	var reach := half.length()
	var lo := _to_px(centre - Vector2(reach, reach))
	var hi := _to_px(centre + Vector2(reach, reach))
	var edge_m := 1.2 / PIXELS_PER_METRE
	for y in range(maxi(floori(lo.y), 0), mini(ceili(hi.y), size.y)):
		for x in range(maxi(floori(lo.x), 0), mini(ceili(hi.x), size.x)):
			var world := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) / PIXELS_PER_METRE
			var d := world - centre
			var u := absf(d.dot(ax))
			var v := absf(d.dot(az))
			if u <= half.x and v <= half.y:
				image.set_pixel(x, y, edge if (u > half.x - edge_m or v > half.y - edge_m) else fill)
