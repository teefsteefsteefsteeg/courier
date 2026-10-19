class_name EnhancementGlow
extends Node3D
## The enhancement effect of a held weapon (or shield), built under its held model so it
## follows every swing (Phase 8 rework: one distinct, animated element per level, not one
## glow in five colours). Flipbooks come from the Super Pixel Effects Gigapack
## (assets/vfx/enhancement/, VfxStrip); motes, leaves, droplets and embers are
## CPUParticles3D in world space, so they trail behind a moving weapon.
##   +1 SILVER SPARK   spark bursts and glints along the blade, drifting silver motes
##   +2 NATURE ENERGY  green sparkle bursts, leaves spiralling up the weapon
##   +3 WATER          a swirl of droplets round the weapon, bubbles, dripping water
##   +4 LIGHTNING      purple crackling aura, bolt flashes, a flickering violet light
##   +5 LEGENDARY      flames along the weapon, lightning, a water ring and rising embers,
##                     a flickering fire light
## Placement follows the weapon: along the blade (sword), round the head (axe), the whole
## bow, the top of the staff, the face of a shield. EnhancementVisuals creates and removes it.

const TIER_NAMES: Array[String] = ["", "Silver Spark", "Nature Energy", "Water", "Lightning", "Legendary"]

## Where effects sit along the grip-to-tip axis (0 = grip, 1 = tip; negative = the other
## side of the grip, for a bow held in the middle), per weapon type.
const SPAN := {
	ItemDefinition.WeaponType.SWORD: Vector2(0.3, 1.0),
	ItemDefinition.WeaponType.AXE: Vector2(0.62, 1.0),
	ItemDefinition.WeaponType.BOW: Vector2(-0.9, 0.9),
	ItemDefinition.WeaponType.STAFF: Vector2(0.72, 1.0),
	ItemDefinition.WeaponType.NONE: Vector2(0.2, 0.8),
}

const OVER_BODY_PRIORITY := 10
const BOW_SIZE := 1.3

var level: int = 0
## True for a bow's effects, which draw over the courier's body (see _show_over_body).
var shows_over_body := false
## The tier's elements, for tests: &"spark", &"glint", &"motes", &"nature", &"leaves",
## &"swirl", &"bubbles", &"drips", &"crackle", &"bolt", &"flame", &"embers", &"light".
var elements: Array[StringName] = []
## Grip-to-tip axis end in the held model's space (for tests and placement).
var tip: Vector3 = Vector3.ZERO
var strips: Array[VfxStrip] = []
var particles: Array[CPUParticles3D] = []
var light: OmniLight3D = null
var _base: Vector3
var _span := Vector2(0.3, 1.0)
var _light_energy := 0.0
var _flicker := 0.0

static var _textures: Dictionary = {}


## Builds the effect for an item at item_level (1-5) under held, the held model node (in
## the tree, so its meshes' extent is known). weapon_type picks the placement. Null at +0.
static func build(held: Node3D, item_level: int, weapon_type: ItemDefinition.WeaponType = ItemDefinition.WeaponType.SWORD) -> EnhancementGlow:
	item_level = Enhancement.clamp_level(item_level)
	if held == null or item_level <= 0:
		return null
	var glow := EnhancementGlow.new()
	glow.name = "EnhancementGlow"
	glow.level = item_level
	glow._span = SPAN.get(weapon_type, SPAN[ItemDefinition.WeaponType.NONE])
	var box := local_bounds(held)
	var axis := longest_axis(box)
	# The grip is at the model origin; the tip is the far end of the longest axis.
	var near_end := box.position[axis]
	var far_end := box.end[axis]
	var tip_value := far_end if absf(far_end) >= absf(near_end) else near_end
	glow._base = box.get_center()
	glow._base[axis] = 0.0
	glow.tip = glow._base
	glow.tip[axis] = tip_value
	held.add_child(glow)
	glow._populate()
	if weapon_type == ItemDefinition.WeaponType.BOW:
		glow._show_over_body()
	return glow


## A point at t along the weapon's span (0..1 from the span's start to its end).
func along(t: float) -> Vector3:
	return _base.lerp(tip, lerpf(_span.x, _span.y, t))


func _populate() -> void:
	match level:
		1: _silver_spark()
		2: _nature()
		3: _water()
		4: _lightning()
		5: _legendary()


func _process(delta: float) -> void:
	if light == null:
		return
	_flicker += delta
	light.light_energy = _light_energy * (0.8 + 0.2 * sin(_flicker * 23.0) * sin(_flicker * 7.3))


# --- tiers ---------------------------------------------------------------------

func _silver_spark() -> void:
	var silver := Color(0.88, 0.93, 1.0)
	for i in 2:
		var spark := _strip(&"spark", &"spark", 0.42, Color(silver, 1.0), false, along(0.45 + 0.5 * i))
		spark.repeat_every = 1.3
		spark.delay(0.65 * i)
	_strip(&"glint", &"sparkle", 0.34, Color(silver, 0.9), true, along(0.7), 5)
	_particles(&"motes", "dot", 10, 0.05, silver, 0.9, Vector3(0, 0.25, 0), 0.0)


func _nature() -> void:
	for i in 3:
		var bloom := _strip(&"nature", &"nature_burst", 0.5, Color.WHITE, false, along(0.25 + 0.37 * i))
		bloom.repeat_every = 1.5
		bloom.delay(0.5 * i)
	_particles(&"leaves", "leaf", 14, 0.13, Color(0.45, 0.95, 0.35), 1.4, Vector3(0, 0.45, 0), 1.6)
	_particles(&"motes", "dot", 8, 0.05, Color(0.7, 1.0, 0.5), 1.0, Vector3(0, 0.3, 0), 0.0)


func _water() -> void:
	var water := Color(0.35, 0.72, 1.0)
	_strip(&"swirl", &"swirl", 0.85, Color(water, 0.95), true, along(0.55))
	var bubbles := _strip(&"bubbles", &"bubbles", 0.55, Color(0.6, 0.88, 1.0, 0.9), false, along(0.95))
	bubbles.repeat_every = 2.2
	_particles(&"drips", "dot", 12, 0.06, water, 0.8, Vector3(0, -2.5, 0), 0.0)
	_add_light(water, 0.6)


func _lightning() -> void:
	var violet := Color(0.72, 0.42, 1.0)
	_strip(&"crackle", &"aura", 0.62, Color(violet, 0.95), true, along(0.4))
	_strip(&"crackle", &"aura", 0.5, Color(violet, 0.85), true, along(0.9), 8)
	for i in 2:
		var bolt := _strip(&"bolt", &"bolt_flash", 0.48, Color.WHITE, false, along(0.3 + 0.6 * i))
		bolt.repeat_every = 0.9 + 0.35 * i
		bolt.delay(0.45 * i)
	_add_light(violet, 1.1)


func _legendary() -> void:
	# Fire along the outer blade, lightning wrapped over it, water held near the grip, so
	# all three read at once.
	for i in 3:
		var flame := _strip(&"flame", &"flame" if i % 2 == 0 else &"flame_b", 0.34, Color(1, 1, 1, 0.95), true, along(0.35 + 0.3 * i), i * 2)
		flame.offset.y = 20.0
	_strip(&"crackle", &"aura", 0.85, Color(0.78, 0.5, 1.0, 1.0), true, along(0.65), 4)
	var ring := _strip(&"swirl", &"swirl", 0.95, Color(0.4, 0.78, 1.0, 1.0), true, along(0.05), 2)
	ring.name = "Vfx_water_ring"
	var bolt := _strip(&"bolt", &"bolt_flash", 0.55, Color.WHITE, false, along(1.0))
	bolt.repeat_every = 1.1
	_particles(&"embers", "dot", 14, 0.05, Color(1.0, 0.62, 0.2), 1.1, Vector3(0, 0.9, 0), 0.0)
	_particles(&"drips", "dot", 8, 0.06, Color(0.4, 0.78, 1.0), 0.8, Vector3(0, -2.5, 0), 0.0)
	_add_light(Color(1.0, 0.6, 0.25), 1.6)


# --- builders ------------------------------------------------------------------

## The courier holds a bow across the body, so from the iso camera most of it is behind the
## courier and its effects were hidden. The bow's flipbooks and particles draw over the
## body (no depth test, drawn after it) and a little larger.
func _show_over_body() -> void:
	shows_over_body = true
	for sprite in strips:
		var material := sprite.material_override as StandardMaterial3D
		material.no_depth_test = true
		material.render_priority = OVER_BODY_PRIORITY
		sprite.pixel_size *= BOW_SIZE
	for emitter in particles:
		var quad := emitter.mesh as QuadMesh
		quad.size *= BOW_SIZE
		var material := quad.material as StandardMaterial3D
		material.no_depth_test = true
		material.render_priority = OVER_BODY_PRIORITY


## A flipbook (VfxStrip of source) at a point of the weapon, recorded as element.
func _strip(element: StringName, source: StringName, size: float, tint: Color, looping: bool, at: Vector3, start_frame: int = 0) -> VfxStrip:
	var sprite := VfxStrip.create(source, size, tint, looping, start_frame)
	sprite.name = "Vfx_%s_%d" % [element, strips.size()]
	sprite.position = at
	add_child(sprite)
	strips.append(sprite)
	if not elements.has(element):
		elements.append(element)
	return sprite


## World-space particles emitted along the weapon's span (so they trail behind a swing).
func _particles(kind: StringName, texture: String, amount: int, size: float, color: Color, lifetime: float, gravity: Vector3, spin: float) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.name = "Particles_" + String(kind)
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.local_coords = false
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	var points := PackedVector3Array()
	for i in 9:
		points.append(along(i / 8.0))
	emitter.emission_points = points
	emitter.direction = Vector3.UP
	emitter.spread = 70.0
	emitter.initial_velocity_min = 0.05
	emitter.initial_velocity_max = 0.35
	emitter.gravity = gravity
	emitter.angular_velocity_min = -spin * 90.0
	emitter.angular_velocity_max = spin * 90.0
	emitter.angle_max = 360.0 if spin > 0.0 else 0.0
	emitter.scale_amount_min = 0.7
	emitter.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(color, 0.0))
	fade.add_point(0.15, Color(color, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(color, 0.0))
	emitter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := _additive(_texture(texture), Color.WHITE)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	emitter.mesh = quad
	add_child(emitter)
	particles.append(emitter)
	if not elements.has(kind):
		elements.append(kind)
	return emitter


func _add_light(color: Color, energy: float) -> void:
	light = OmniLight3D.new()
	light.name = "GlowLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 1.9
	light.shadow_enabled = false
	light.position = along(0.6)
	_light_energy = energy
	add_child(light)
	if not elements.has(&"light"):
		elements.append(&"light")


## Procedural sprites shared by every glow: "dot" (soft round mote / droplet / ember) and
## "leaf" (a pointed leaf with a mid-rib).
static func _texture(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var u := (x - 15.5) / 16.0
			var v := (y - 15.5) / 16.0
			var a := 0.0
			if kind == "leaf":
				var width := 0.42 * (1.0 - v * v)
				a = clampf((width - absf(u)) * 6.0, 0.0, 1.0) if absf(v) < 1.0 else 0.0
				if absf(u) < 0.05 and v > -0.85:
					a *= 0.55
			else:
				a = clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
				a *= a
			image.set_pixel(x, y, Color(1, 1, 1, a))
	var texture := ImageTexture.create_from_image(image)
	_textures[kind] = texture
	return texture


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
