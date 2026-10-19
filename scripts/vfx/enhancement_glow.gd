class_name EnhancementGlow
extends Node3D
## The glow of an enhanced weapon (or shield), built under its held model so it follows
## every swing. Effects sit along the model's longest axis, from the grip out to the tip,
## in Enhancement.level_color, over a soft sheen that brightens with the level:
##   +1  two sparkles                  +4  four sparkles, aura, a coloured light
##   +2  three brighter sparkles       +5  golden: five sparkles, aura, light and a
##   +3  three sparkles and an aura        burst at the tip every BURST_EVERY seconds
## EnhancementVisuals creates and removes it.

const BURST_EVERY := 1.8
const SPARKLES: Array[int] = [0, 2, 3, 3, 4, 5]
## Soft glow beads along the blade (every level; brighter per level).
const SHEEN_BEADS := 6

var level: int = 0
var sheen: Array[Sprite3D] = []
## Grip-to-tip axis in the held model's space (for tests and placement).
var tip: Vector3 = Vector3.ZERO
var sparkles: Array[VfxStrip] = []
var aura: VfxStrip = null
var light: OmniLight3D = null
var burst: VfxStrip = null


## Builds the glow for an item at `level` (1-5) under held, the held model node (in the
## tree, so its meshes' extent is known). Null for level 0.
static func build(held: Node3D, item_level: int) -> EnhancementGlow:
	item_level = Enhancement.clamp_level(item_level)
	if held == null or item_level <= 0:
		return null
	var glow := EnhancementGlow.new()
	glow.name = "EnhancementGlow"
	glow.level = item_level
	var box := local_bounds(held)
	var axis := longest_axis(box)
	# The grip is at the model origin; the tip is the far end of the longest axis.
	var near_end := box.position[axis]
	var far_end := box.end[axis]
	var tip_value := far_end if absf(far_end) >= absf(near_end) else near_end
	var center := box.get_center()
	center[axis] = 0.0
	glow.tip = center
	glow.tip[axis] = tip_value
	held.add_child(glow)
	glow._populate(center, glow.tip, box.size[axis] * _world_scale(held))
	return glow


func _populate(base: Vector3, tip_point: Vector3, world_length: float) -> void:
	var color := Enhancement.level_color(level)
	# A soft sheen hugs the blade at every level, stronger as the level rises.
	var sheen_texture := _sheen_texture()
	for i in SHEEN_BEADS:
		var bead := Sprite3D.new()
		bead.name = "Sheen%d" % i
		bead.texture = sheen_texture
		bead.pixel_size = (0.2 + 0.02 * level) / float(sheen_texture.get_width())
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bead.material_override = _additive(sheen_texture, Color(color, 0.22 + 0.08 * level))
		bead.position = base.lerp(tip_point, 0.3 + 0.7 * float(i) / float(SHEEN_BEADS - 1))
		add_child(bead)
		sheen.append(bead)
	var count := SPARKLES[level]
	for i in count:
		var t := 0.3 + 0.7 * (float(i) + 0.5) / float(count)
		var spark := VfxStrip.create(&"sparkle", 0.3 + 0.05 * level, Color(color, minf(0.8 + 0.05 * level, 1.0)), true, i * 7)
		spark.position = base.lerp(tip_point, t)
		add_child(spark)
		sparkles.append(spark)
	if level >= 3:
		aura = VfxStrip.create(&"aura", clampf(world_length * 0.85, 0.45, 1.2), Color(color, 0.35 + 0.1 * (level - 3)), true)
		aura.position = base.lerp(tip_point, 0.62)
		add_child(aura)
	if level >= 4:
		light = OmniLight3D.new()
		light.name = "GlowLight"
		light.light_color = color
		light.light_energy = 0.8 if level == 4 else 1.4
		light.omni_range = 1.8
		light.shadow_enabled = false
		light.position = base.lerp(tip_point, 0.6)
		add_child(light)
	if level >= 5:
		burst = VfxStrip.create(&"burst", 0.55, Color(1.0, 0.92, 0.6, 0.9), false)
		burst.repeat_every = BURST_EVERY
		burst.position = tip_point
		add_child(burst)


static var _sheen: Texture2D = null


## A soft white dot (radial gradient), shared by every sheen bead.
static func _sheen_texture() -> Texture2D:
	if _sheen == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		_sheen = texture
	return _sheen


static func _additive(texture: Texture2D, tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = tint
	return material


## Bounds of every mesh under node, in node's own space.
static func local_bounds(node: Node3D) -> AABB:
	var to_local := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = (to_local * mesh.global_transform) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


static func longest_axis(box: AABB) -> int:
	var size := box.size
	if size.x >= size.y and size.x >= size.z:
		return Vector3.AXIS_X
	return Vector3.AXIS_Y if size.y >= size.z else Vector3.AXIS_Z


static func _world_scale(node: Node3D) -> float:
	var scale := node.global_transform.basis.get_scale()
	return (absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0
