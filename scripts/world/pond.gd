@tool
class_name Pond
extends Node3D
## A small pond (Phase 5H; the village had no water): an irregular water surface with a
## muddy shore band, invisible walls along the shore so the courier cannot walk in (with an
## optional gap for a jetty), and the fish that live in it. Group "water": the fishing rod
## only casts where is_open_water() says so, which keeps fishing off dry land.
## Built procedurally in _ready from radius_x/radius_z and the outline noise, so it needs
## no mesh assets and can be resized in the editor.

const GROUP := &"water"

@export_range(1.0, 20.0, 0.1, "suffix:m") var radius_x: float = 5.0:
	set(value):
		radius_x = value
		_rebuild()
@export_range(1.0, 20.0, 0.1, "suffix:m") var radius_z: float = 4.0:
	set(value):
		radius_z = value
		_rebuild()
@export var outline_seed: int = 7:
	set(value):
		outline_seed = value
		_rebuild()
## Water surface height above the (flat) ground.
@export var water_height: float = 0.05
## Shoreline gap for a jetty: direction (local XZ, degrees, 0 = +X towards -Z) and width.
@export var jetty_angle_degrees: float = -1.0
@export var jetty_width: float = 1.6
@export var jetty_length: float = 3.0
@export_group("Fish")
## What bites here, with relative weights.
@export var fish: Array[MaterialItem] = []
@export var fish_weights: PackedFloat32Array = PackedFloat32Array()
## Fish at or after this index count as rare (luck bonuses raise their weight).
@export var rare_from: int = 2

const SEGMENTS := 48
const WALL_HEIGHT := 1.6

var _built := false


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_rebuild()


## Distance from the centre to the shore along local angle (radians).
func shore_radius(angle: float) -> float:
	var r := Vector2(cos(angle) * radius_x, sin(angle) * radius_z).length()
	var wobble := 1.0 + 0.08 * sin(angle * 3.0 + outline_seed) + 0.05 * sin(angle * 5.0 + outline_seed * 2.1)
	return r * wobble


## True when a world point is over open water, at least margin metres in from the shore.
func is_open_water(world_point: Vector3, margin: float = 0.4) -> bool:
	var local := to_local(world_point)
	var flat := Vector2(local.x, local.z)
	if flat.length() < 0.001:
		return true
	var angle := atan2(flat.y, flat.x)
	return flat.length() <= shore_radius(angle) - margin


## The water surface height in world space.
func get_water_y() -> float:
	return global_position.y + water_height


## Picks a fish by weight. rare_bonus multiplies the weight of rare fish (index >= rare_from).
func pick_fish(rng: RandomNumberGenerator, rare_bonus: float = 1.0) -> MaterialItem:
	if fish.is_empty():
		return null
	var weights: Array[float] = []
	var total := 0.0
	for i in fish.size():
		var weight := fish_weights[i] if i < fish_weights.size() else 1.0
		if i >= rare_from:
			weight *= rare_bonus
		weights.append(weight)
		total += weight
	var roll := rng.randf() * total
	for i in fish.size():
		roll -= weights[i]
		if roll <= 0.0:
			return fish[i]
	return fish[fish.size() - 1]


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.has_meta(&"pond_generated"):
			remove_child(child)
			child.free()
	_add_mesh("Shore", _disc_mesh(0.9, 0.02), _shore_material())
	_add_mesh("Water", _disc_mesh(0.0, water_height), _water_material())
	_add_walls()


func _add_mesh(node_name: String, mesh: Mesh, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(&"pond_generated", true)
	add_child(node)


## A fan over the pond outline grown by `grow` metres, at height y. Vertex colour alpha is
## 1 at the centre and 0 at the rim (the water shader darkens the deep middle with it).
func _disc_mesh(grow: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var p0 := Vector3(cos(a0), 0, sin(a0)) * (shore_radius(a0) + grow)
		var p1 := Vector3(cos(a1), 0, sin(a1)) * (shore_radius(a1) + grow)
		for v in [[Vector3.ZERO, 1.0], [p1, 0.0], [p0, 0.0]]:
			st.set_color(Color(1, 1, 1, v[1]))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v[0].x, v[0].z) * 0.25)
			st.add_vertex(v[0] + Vector3.UP * y)
	return st.commit()


func _water_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform vec3 shallow : source_color = vec3(0.32, 0.62, 0.66);
uniform vec3 deep : source_color = vec3(0.10, 0.30, 0.42);
void fragment() {
	float depth = smoothstep(0.0, 0.8, COLOR.a);
	vec2 p = UV * 6.0;
	float ripple = sin(p.x * 1.7 + TIME * 1.3) * sin(p.y * 1.3 - TIME * 1.1);
	ALBEDO = mix(shallow, deep, depth) + ripple * 0.025;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.78, 0.94, depth);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _shore_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.34, 0.24)
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = false
	return material


## Invisible walls just inside the shore (the courier stands on the bank's edge), leaving a
## gap for the jetty when jetty_angle_degrees >= 0, plus the jetty's side and end walls.
func _add_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "ShoreWalls"
	body.set_meta(&"pond_generated", true)
	add_child(body)
	var faces := PackedVector3Array()
	var gap := deg_to_rad(jetty_angle_degrees)
	var has_gap := jetty_angle_degrees >= 0.0
	var inset := 0.35
	var points: Array[Vector3] = []
	for i in SEGMENTS + 1:
		var a := TAU * i / SEGMENTS
		points.append(Vector3(cos(a), 0, sin(a)) * maxf(shore_radius(a) - inset, 0.2))
	for i in SEGMENTS:
		var mid := TAU * (i + 0.5) / SEGMENTS
		var r := shore_radius(mid)
		if has_gap and absf(angle_difference(mid, gap)) * r < jetty_width * 0.5 + 0.25:
			continue
		_wall(faces, points[i], points[i + 1])
	if has_gap:
		var dir := Vector3(cos(gap), 0, sin(gap))
		var side := Vector3(-dir.z, 0, dir.x) * jetty_width * 0.5
		var base := dir * (shore_radius(gap) + 0.2)
		var tip := dir * maxf(shore_radius(gap) - jetty_length, 0.5)
		_wall(faces, base + side, tip + side)
		_wall(faces, base - side, tip - side)
		_wall(faces, tip + side, tip - side)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)


func _wall(faces: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var up := Vector3.UP * WALL_HEIGHT
	faces.append_array([a, b, b + up, a, b + up, a + up])
