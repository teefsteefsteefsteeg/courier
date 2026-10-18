extends RefCounted
## Phase 4 integration visual helpers: shared material loading from
## assets/materials/phase4_integration (private copies with fallback colours,
## mirroring Lowpoly.load_material) and overlay setup for world-space UI that
## must stay readable through foliage (enemy health bars).

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const MATERIAL_DIR := "res://assets/materials/phase4_integration/"
const MATERIALS := [
	"route_marker", "route_flower", "route_flower_stem", "quest_beacon",
	"quest_ring", "quest_gem", "enemy_health_back", "enemy_health_fill",
	"enemy_health_lag", "defeat_burst",
]


## Returns a private copy of a shared material so per-instance tinting and
## fades never leak between instances.
static func load_material(file_name: String, fallback: Color) -> StandardMaterial3D:
	var path := MATERIAL_DIR + file_name
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is StandardMaterial3D:
			return (res as StandardMaterial3D).duplicate() as StandardMaterial3D
	push_warning("Phase 4 integration visual: missing material %s, using fallback" % path)
	return Lowpoly.make_material(fallback)


## Private copy of a shared material recoloured to `color` (alpha included).
static func tinted(file_name: String, color: Color) -> StandardMaterial3D:
	var mat := load_material(file_name, color)
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if mat.emission_enabled:
		mat.emission = Color(color.r, color.g, color.b)
	return mat


## Unshaded, double-sided, always-on-top material sorted by render_priority.
static func make_overlay(mat: StandardMaterial3D, priority: int) -> StandardMaterial3D:
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = priority
	return mat
