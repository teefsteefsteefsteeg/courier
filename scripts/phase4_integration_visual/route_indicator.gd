extends Node3D
## Colourful forest delivery route: glowing faceted stepping-stone markers along
## the path (lime -> teal -> sky -> gold toward the drop-off), a brightness
## pulse that travels toward the destination, low-poly flower tufts along the
## verge, and a quest beacon at the drop-off (light column, rotating ground
## ring, floating gem, label, light). Markers behind the courier dim as
## update_progress() is fed the courier position. Extra quest markers (pickup,
## side objectives) can be pinned with add_marker(). Purely visual.
## Route points are world positions; animation runs from _process or manually
## via advance(delta) when auto_animate is false.

signal progress_changed(index: int, count: int)
signal quest_state_changed(state: StringName)

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const Assets := preload("res://scripts/phase4_integration_visual/integration_assets.gd")
const ROUTE_GRADIENT := [
	Color(0.55, 1.0, 0.35), Color(0.3, 0.95, 0.75), Color(0.4, 0.75, 1.0), Color(1.0, 0.85, 0.3),
]
const FLOWER_COLORS := [
	Color(1.0, 0.45, 0.7), Color(1.0, 0.85, 0.3), Color(0.7, 0.5, 1.0), Color(1.0, 0.55, 0.3),
]
const STATE_COLORS := {
	&"available": Color(0.4, 0.85, 1.0),
	&"active": Color(1.0, 0.85, 0.3),
	&"complete": Color(0.45, 1.0, 0.5),
	&"failed": Color(1.0, 0.35, 0.3),
}
const MARKER_ALPHA := 0.85
const PASSED_ALPHA := 0.22
const GEM_HEIGHT := 2.2

@export var auto_animate := true
@export var marker_spacing := 1.4
@export var max_markers := 64
@export var marker_size := 0.22
@export var marker_height := 0.06
@export var decorate := true
## Markers per second the brightness pulse travels toward the destination.
@export var pulse_speed := 6.0
@export var beacon_height := 6.0
@export var beacon_text := "Drop-off"

var route_points := PackedVector3Array()  ## local space
var markers: Array[MeshInstance3D] = []
var marker_materials: Array[StandardMaterial3D] = []
var marker_colors: Array[Color] = []
var flowers: Array[Node3D] = []
var progress_index := 0
var quest_state: StringName = &"active"
var destination := Vector3.INF  ## local space
var beacon: Node3D
var beacon_column: MeshInstance3D
var beacon_ring: MeshInstance3D
var beacon_gem: MeshInstance3D
var beacon_label: Label3D
var beacon_light: OmniLight3D
var beacon_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var gem_material: StandardMaterial3D
var extra_markers: Dictionary = {}  ## StringName id -> Node3D

var _markers_root: Node3D
var _flowers_root: Node3D
var _flower_materials: Dictionary = {}  ## Color -> StandardMaterial3D
var _stem_material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_ensure_roots()
	_apply()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


# --- route ---------------------------------------------------------------------

## Lays markers along a world-space polyline. The last point becomes the
## destination unless set_destination() was already called.
func set_route(world_points: PackedVector3Array) -> void:
	clear_route()
	for p in world_points:
		route_points.append(_local(p))
	if route_points.size() < 2:
		return
	_build_markers()
	if not has_destination():
		set_destination(world_points[world_points.size() - 1], beacon_text)
	_apply()


func clear_route() -> void:
	_ensure_roots()
	for node in markers:
		if is_instance_valid(node):
			node.queue_free()
	for node in flowers:
		if is_instance_valid(node):
			node.queue_free()
	markers.clear()
	marker_materials.clear()
	marker_colors.clear()
	flowers.clear()
	route_points = PackedVector3Array()
	progress_index = 0


func get_marker_count() -> int:
	return markers.size()


func get_route_length() -> float:
	var total := 0.0
	for i in range(route_points.size() - 1):
		total += route_points[i].distance_to(route_points[i + 1])
	return total


## Dims markers behind the nearest one to the courier. Returns the index.
func update_progress(world_position: Vector3) -> int:
	if markers.is_empty():
		return 0
	var here := _local(world_position)
	var best := 0
	var best_d := INF
	for i in markers.size():
		var p := markers[i].position
		var d := Vector2(p.x - here.x, p.z - here.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	if best != progress_index:
		progress_index = best
		progress_changed.emit(progress_index, markers.size())
		_apply()
	return progress_index


func get_marker_color(index: int) -> Color:
	return marker_materials[index].albedo_color if index >= 0 and index < marker_materials.size() else Color.TRANSPARENT


static func gradient_color(t: float) -> Color:
	var n := ROUTE_GRADIENT.size()
	var x := clampf(t, 0.0, 1.0) * float(n - 1)
	var i := mini(int(floor(x)), n - 2)
	var a: Color = ROUTE_GRADIENT[i]
	var b: Color = ROUTE_GRADIENT[i + 1]
	return a.lerp(b, x - float(i))


# --- destination / quest -------------------------------------------------------

func set_destination(world_position: Vector3, text := "") -> void:
	_ensure_beacon()
	destination = _local(world_position)
	beacon.position = destination
	beacon_label.text = text if text != "" else beacon_text
	beacon.visible = true
	_apply_state_colors()
	_apply()


func clear_destination() -> void:
	destination = Vector3.INF
	if beacon != null:
		beacon.visible = false


func has_destination() -> bool:
	return destination.is_finite()


func get_destination_world() -> Vector3:
	if not has_destination():
		return Vector3.INF
	return to_global(destination) if is_inside_tree() else destination


## Ground-plane distance from a world position to the drop-off (-1 if none).
func get_distance_to_destination(world_position: Vector3) -> float:
	if not has_destination():
		return -1.0
	var d := get_destination_world()
	return Vector2(d.x - world_position.x, d.z - world_position.z).length()


## state: &"available", &"active", &"complete", &"failed" or &"hidden".
func set_quest_state(state: StringName) -> void:
	if state == quest_state:
		return
	quest_state = state
	visible = state != &"hidden"
	_apply_state_colors()
	_apply()
	quest_state_changed.emit(state)


func get_state_color() -> Color:
	return STATE_COLORS.get(quest_state, STATE_COLORS[&"active"])


func get_beacon_color() -> Color:
	return gem_material.albedo_color if gem_material != null else Color.TRANSPARENT


## Pins a floating quest marker (pickup, side objective) at a world position.
func add_marker(id: StringName, world_position: Vector3, text := "", color := Color(0.4, 0.85, 1.0)) -> Node3D:
	remove_marker(id)
	var root := Node3D.new()
	root.name = "QuestMarker_%s" % String(id)
	root.position = _local(world_position)
	add_child(root)
	var gem_mat := Assets.tinted("quest_gem.tres", color)
	var gem := Lowpoly.add_part(root, "Gem", Lowpoly.sphere(0.22, 0.44, 4, 2), gem_mat, Vector3(0, 1.6, 0), false)
	gem.set_meta(&"base_height", 1.6)
	var ring_mat := Assets.tinted("quest_ring.tres", Color(color.r, color.g, color.b, 0.75))
	Lowpoly.add_part(root, "Ring", Lowpoly.ring(0.45, 0.6, 12), ring_mat, Vector3(0, 0.05, 0), false)
	if text != "":
		var label := _make_label(text, 40)
		label.position = Vector3(0, 2.2, 0)
		root.add_child(label)
	extra_markers[id] = root
	return root


func remove_marker(id: StringName) -> void:
	if extra_markers.has(id):
		var node = extra_markers[id]
		if is_instance_valid(node):
			(node as Node).queue_free()
		extra_markers.erase(id)


func advance(delta: float) -> void:
	_time += delta
	_apply()


# --- view ----------------------------------------------------------------------

func _apply() -> void:
	var n := markers.size()
	var cycle := float(n + 6)
	var state_color := get_state_color()
	for i in n:
		var base := marker_colors[i]
		if quest_state == &"complete":
			base = base.lerp(state_color, 0.6)
		elif quest_state == &"failed":
			base = base.lerp(state_color, 0.7)
		var phase := fposmod(_time * pulse_speed - float(i), cycle)
		var glow := clampf(1.0 - phase / 3.0, 0.0, 1.0)
		var passed := i < progress_index
		var c := base.lerp(Color.WHITE, glow * 0.45)
		c.a = PASSED_ALPHA if passed else MARKER_ALPHA
		marker_materials[i].albedo_color = c
		var marker := markers[i]
		marker.position.y = marker_height + (0.0 if passed else glow * 0.08)
		marker.scale = Vector3.ONE * (0.75 if passed else 1.0 + glow * 0.25)
	for i in flowers.size():
		var flower := flowers[i]
		if is_instance_valid(flower):
			flower.rotation.z = sin(_time * 1.6 + float(i) * 1.7) * 0.12
	if beacon != null and beacon.visible:
		beacon_ring.rotation.y = _time * 1.2
		beacon_gem.position.y = GEM_HEIGHT + sin(_time * 2.0) * 0.18
		beacon_gem.rotation.y = _time * 1.6
		var col := beacon_material.albedo_color
		col.a = 0.28 + 0.1 * sin(_time * 3.0)
		beacon_material.albedo_color = col
	for id in extra_markers:
		var node = extra_markers[id]
		if is_instance_valid(node):
			var gem := (node as Node).get_node_or_null(^"Gem") as Node3D
			if gem != null:
				gem.position.y = float(gem.get_meta(&"base_height", 1.6)) + sin(_time * 2.4 + float((node as Node).get_index())) * 0.12
				gem.rotation.y = _time * 1.8


func _apply_state_colors() -> void:
	if beacon == null:
		return
	var c := get_state_color()
	beacon_material.albedo_color = Color(c.r, c.g, c.b, 0.35)
	ring_material.albedo_color = Color(c.r, c.g, c.b, 0.8)
	gem_material.albedo_color = c.lightened(0.15)
	gem_material.emission = c
	beacon_light.light_color = c


func _build_markers() -> void:
	_ensure_roots()
	var spacing := maxf(marker_spacing, get_route_length() / float(maxi(max_markers, 1)))
	var samples := _sample_route(spacing)
	var mesh := Lowpoly.cone(marker_size, marker_size, 0.05, 4)  # square slab turned to a diamond
	var count := samples.size()
	for i in count:
		var sample: Array = samples[i]
		var at: Vector3 = sample[0]
		var yaw: float = sample[1]
		var color := gradient_color(float(i) / float(maxi(count - 1, 1)))
		var mat := Assets.tinted("route_marker.tres", Color(color.r, color.g, color.b, MARKER_ALPHA))
		var marker := Lowpoly.add_part(_markers_root, "Marker%d" % i, mesh, mat, at + Vector3(0, marker_height, 0), false)
		marker.rotation.y = yaw + PI * 0.25
		markers.append(marker)
		marker_materials.append(mat)
		marker_colors.append(color)
		if decorate and i % 2 == 0:
			_add_flower(at, yaw, i)


## Evenly spaced [position, yaw] samples along the local polyline.
func _sample_route(spacing: float) -> Array:
	var samples := []
	var next := spacing * 0.5
	var walked := 0.0
	for i in range(route_points.size() - 1):
		var a := route_points[i]
		var b := route_points[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var dir := (b - a) / seg
		var yaw := atan2(dir.x, dir.z)
		while next <= walked + seg and samples.size() < max_markers:
			samples.append([a + dir * (next - walked), yaw])
			next += spacing
		walked += seg
	return samples


func _add_flower(at: Vector3, yaw: float, index: int) -> void:
	var side := 1.0 if (index / 2) % 2 == 0 else -1.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var flower := Node3D.new()
	flower.name = "Flower%d" % index
	flower.position = at + right * side * (0.8 + 0.25 * sin(float(index)))
	_flowers_root.add_child(flower)
	if _stem_material == null:
		_stem_material = Assets.load_material("route_flower_stem.tres", Color(0.24, 0.55, 0.2))
	var color: Color = FLOWER_COLORS[(index / 2) % FLOWER_COLORS.size()]
	if not _flower_materials.has(color):
		_flower_materials[color] = Assets.tinted("route_flower.tres", color)
	Lowpoly.add_part(flower, "Stem", Lowpoly.cone(0.02, 0.015, 0.24, 4), _stem_material, Vector3(0, 0.12, 0))
	Lowpoly.add_part(flower, "Bloom", Lowpoly.sphere(0.1, 0.12, 5, 2), _flower_materials[color], Vector3(0, 0.26, 0))
	flowers.append(flower)


func _ensure_roots() -> void:
	if _markers_root != null:
		return
	_markers_root = Node3D.new()
	_markers_root.name = "Markers"
	add_child(_markers_root)
	_flowers_root = Node3D.new()
	_flowers_root.name = "Flowers"
	add_child(_flowers_root)


func _ensure_beacon() -> void:
	if beacon != null:
		return
	beacon = Node3D.new()
	beacon.name = "QuestBeacon"
	add_child(beacon)
	beacon_material = Assets.load_material("quest_beacon.tres", Color(1.0, 0.85, 0.3, 0.35))
	beacon_column = Lowpoly.add_part(beacon, "LightColumn", Lowpoly.cone(0.45, 0.12, beacon_height, 6), beacon_material, Vector3(0, beacon_height * 0.5, 0), false)
	ring_material = Assets.load_material("quest_ring.tres", Color(1.0, 0.85, 0.3, 0.8))
	beacon_ring = Lowpoly.add_part(beacon, "GroundRing", Lowpoly.ring(0.95, 1.2, 16), ring_material, Vector3(0, 0.05, 0), false)
	gem_material = Assets.load_material("quest_gem.tres", Color(1.0, 0.9, 0.45))
	beacon_gem = Lowpoly.add_part(beacon, "Gem", Lowpoly.sphere(0.3, 0.6, 4, 2), gem_material, Vector3(0, GEM_HEIGHT, 0), false)
	beacon_label = _make_label(beacon_text, 56)
	beacon_label.name = "Label"
	beacon_label.position = Vector3(0, GEM_HEIGHT + 0.9, 0)
	beacon.add_child(beacon_label)
	beacon_light = OmniLight3D.new()
	beacon_light.name = "BeaconLight"
	beacon_light.light_energy = 1.2
	beacon_light.omni_range = 5.0
	beacon_light.position = Vector3(0, 1.2, 0)
	beacon.add_child(beacon_light)
	beacon.visible = false


func _make_label(text: String, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = size
	label.outline_size = 12
	label.pixel_size = 0.006
	label.modulate = Color(1.0, 0.97, 0.88)
	return label


func _local(world_position: Vector3) -> Vector3:
	return to_local(world_position) if is_inside_tree() else world_position
