extends RefCounted
## Phase 4 visual helpers: procedural low-poly meshes and combat materials.
## Every mesh is generated from a Godot PrimitiveMesh and re-emitted with flat
## (per-face) normals so creatures and props read as faceted low-poly shapes.
## No external assets are used.

const MATERIAL_DIR := "res://assets/materials/combat/"


## Re-emits a primitive mesh as a non-indexed ArrayMesh with flat normals.
## The triangle count is stored as meta "triangle_count" for budget checks.
static func faceted(source: PrimitiveMesh) -> ArrayMesh:
	var arrays: Array = source.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		normals = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for i in verts.size():
			indices.append(i)

	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var has_normals := normals.size() == verts.size()
	for i in range(0, indices.size() - 2, 3):
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		var a := verts[ia]
		var b := verts[ib]
		var c := verts[ic]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue  # degenerate pole triangles
		n = n.normalized()
		if has_normals and n.dot(normals[ia] + normals[ib] + normals[ic]) < 0.0:
			n = -n
		for v in [a, b, c]:
			out_verts.append(v)
			out_normals.append(n)

	var mesh := ArrayMesh.new()
	if not out_verts.is_empty():
		var surface := []
		surface.resize(Mesh.ARRAY_MAX)
		surface[Mesh.ARRAY_VERTEX] = out_verts
		surface[Mesh.ARRAY_NORMAL] = out_normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	mesh.set_meta(&"triangle_count", int(out_verts.size() / 3.0))
	return mesh


static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	return int(mesh.get_meta(&"triangle_count", 0))


static func sphere(radius: float, height: float, radial: int, rings: int) -> ArrayMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = radial
	m.rings = rings
	return faceted(m)


static func cone(bottom: float, top: float, height: float, radial: int) -> ArrayMesh:
	var m := CylinderMesh.new()
	m.bottom_radius = bottom
	m.top_radius = top
	m.height = height
	m.radial_segments = radial
	m.rings = 1
	return faceted(m)


static func box(size: Vector3) -> ArrayMesh:
	var m := BoxMesh.new()
	m.size = size
	return faceted(m)


static func prism(size: Vector3) -> ArrayMesh:
	var m := PrismMesh.new()
	m.size = size
	return faceted(m)


static func capsule(radius: float, height: float, radial: int, rings: int) -> ArrayMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = radial
	m.rings = rings
	return faceted(m)


static func ring(inner: float, outer: float, segments: int) -> ArrayMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segments
	m.ring_segments = 3
	return faceted(m)


static func plane(size: Vector2) -> ArrayMesh:
	var m := PlaneMesh.new()
	m.size = size
	return faceted(m)


## Adds a MeshInstance3D child. Transparent parts should pass casts_shadow = false.
static func add_part(parent: Node3D, part_name: String, mesh: Mesh, material: Material, pos := Vector3.ZERO, casts_shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Loads a shared material from assets/materials/combat and returns a private
## copy (so per-instance hit flashes and fades never leak between instances).
static func load_material(file_name: String, fallback: Color) -> StandardMaterial3D:
	var path := MATERIAL_DIR + file_name
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is StandardMaterial3D:
			return (res as StandardMaterial3D).duplicate() as StandardMaterial3D
	push_warning("Phase 4 visual: missing material %s, using fallback" % path)
	return make_material(fallback)


static func make_material(color: Color, emission_energy := 0.0, unshaded := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = emission_energy
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Sums faceted triangle counts of every MeshInstance3D below node.
static func count_triangles(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += triangle_count((node as MeshInstance3D).mesh)
	for child in node.get_children():
		total += count_triangles(child)
	return total


static func set_alpha(mat: StandardMaterial3D, alpha: float) -> void:
	if mat == null:
		return
	var c := mat.albedo_color
	c.a = clampf(alpha, 0.0, 1.0)
	mat.albedo_color = c
