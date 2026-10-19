class_name GroundFx
extends RefCounted
## World-space combat effects that live in the environment rather than on the weapon
## (Phase 8): decals projected onto whatever terrain is under them (so they follow slopes),
## expanding shockwave rings, glowing fissures, burn marks, rune circles, lightning that
## strikes from the sky, flame patches that keep burning, 3D rock debris, dust, explosions,
## light flashes and camera shake. Every effect is a node under `parent` (the level) that
## frees itself; none of them deals damage (the skills do that). Each returns its root node
## so callers and tests can find it; roots are named "Fx<Kind>".
## Textures: assets/vfx/ground/ (tools/make_ground_vfx.py), the Brackeys fire / explosion /
## smoke flipbooks (assets/vfx/boss/) and the Gigapack strips (VfxStrip).

const DIR := "res://assets/vfx/ground/"
const FIRE_SHEET := "res://assets/vfx/boss/fire_8x8.png"
const EXPLOSION_SHEET := "res://assets/vfx/boss/explosion_8x8.png"
const SMOKE_SHEET := "res://assets/vfx/boss/smoke_8x8.png"
## Only geometry on render layer 1 (terrain, buildings, props) receives ground decals.
const DECAL_CULL_MASK := 1

static var _rng := RandomNumberGenerator.new()


# --- decals ---------------------------------------------------------------------------

## A decal of texture (DIR + name + ".png") size metres across, projected down onto the
## ground around `at`. emission > 0 makes it glow in `tint`.
static func decal(parent: Node, at: Vector3, size: float, texture_name: String, tint: Color, emission: float = 0.0, depth: float = 2.4) -> Decal:
	var node := Decal.new()
	node.name = "Fx" + texture_name.to_pascal_case()
	var texture := load(DIR + texture_name + ".png") as Texture2D
	node.texture_albedo = texture
	node.modulate = tint
	if emission > 0.0:
		# The emission map is premultiplied (black outside the shape): decals ignore alpha there.
		node.texture_emission = load(DIR + texture_name + "_emission.png") as Texture2D
		node.emission_energy = emission
	node.size = Vector3(size, depth, size)
	node.upper_fade = 0.15
	node.lower_fade = 0.3
	node.normal_fade = 0.35
	node.cull_mask = DECAL_CULL_MASK
	parent.add_child(node)
	node.global_position = at
	return node


## Fades a decal (or any node with modulate) out over seconds after hold seconds, then
## frees it.
static func fade_and_free(node: Node, hold: float, seconds: float) -> void:
	var tween := node.create_tween()
	if node is Decal:
		tween.tween_property(node, ^"modulate:a", 0.0, seconds).set_delay(hold)
		tween.parallel().tween_property(node, ^"emission_energy", 0.0, seconds).set_delay(hold)
	else:
		tween.tween_interval(hold + seconds)
	tween.tween_callback(node.queue_free)


## A shockwave ring that expands from `at` to radius over seconds and fades.
static func shock_ring(parent: Node, at: Vector3, radius: float, seconds: float, tint: Color, emission: float = 2.0) -> Decal:
	var ring := decal(parent, at, 0.4, "ring", tint, emission)
	ring.name = "FxShockRing"
	var tween := ring.create_tween()
	tween.tween_property(ring, ^"size", Vector3(radius * 2.0, ring.size.y, radius * 2.0), seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ring, ^"modulate:a", 0.0, seconds * 0.5).set_delay(seconds * 0.5)
	tween.tween_callback(ring.queue_free)
	return ring


## A burn mark that stays for linger seconds, then fades.
static func scorch(parent: Node, at: Vector3, size: float, linger: float = 4.0) -> Decal:
	var mark := decal(parent, at, size, "scorch", Color(1, 1, 1, 0.9))
	mark.name = "FxScorch"
	mark.rotation.y = _rng.randf() * TAU
	fade_and_free(mark, linger, 1.5)
	return mark


## Glowing ground fissures from `at`: they open to size metres, glow, cool to dark and fade.
static func cracks(parent: Node, at: Vector3, size: float, tint: Color, open_seconds: float = 0.35, linger: float = 3.0) -> Decal:
	var fissure := decal(parent, at, size * 0.3, "cracks", tint, 4.0)
	fissure.name = "FxCracks"
	fissure.rotation.y = _rng.randf() * TAU
	var tween := fissure.create_tween()
	tween.tween_property(fissure, ^"size", Vector3(size, fissure.size.y, size), open_seconds).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(fissure, ^"emission_energy", 0.0, linger * 0.6)
	tween.parallel().tween_property(fissure, ^"modulate", Color(0.16, 0.11, 0.08, 0.85), linger * 0.6)
	tween.tween_property(fissure, ^"modulate:a", 0.0, linger * 0.4)
	tween.tween_callback(fissure.queue_free)
	return fissure


## A glowing rune circle on the ground that spins while it lasts.
static func rune_circle(parent: Node, at: Vector3, radius: float, tint: Color, seconds: float) -> Decal:
	var circle := decal(parent, at, radius * 2.0, "rune_circle", Color(tint, 0.0), 3.0)
	circle.name = "FxRuneCircle"
	var spin := circle.create_tween()
	spin.tween_property(circle, ^"rotation:y", TAU * seconds / 6.0, seconds).from(0.0)
	var fade := circle.create_tween()
	fade.tween_property(circle, ^"modulate:a", 1.0, 0.25)
	fade.tween_interval(maxf(seconds - 0.85, 0.0))
	fade.tween_property(circle, ^"modulate:a", 0.0, 0.6)
	fade.parallel().tween_property(circle, ^"emission_energy", 0.0, 0.6)
	fade.tween_callback(circle.queue_free)
	return circle


# --- light ----------------------------------------------------------------------------

## A point light that flashes and dies away.
static func flash(parent: Node, at: Vector3, color: Color, energy: float, light_range: float, seconds: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "FxFlash"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, ^"light_energy", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(light.queue_free)
	return light


# --- lightning -------------------------------------------------------------------------

## A lightning bolt from the sky onto `ground`: a jagged white core in a coloured glow with
## side branches, re-drawn a few times while it flickers, a light flash, a burn mark and a
## spark ring where it lands.
static func lightning_strike(parent: Node, ground: Vector3, tint: Color, height: float = 14.0, width: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "FxLightning"
	parent.add_child(root)
	root.global_position = ground
	var bolt := MeshInstance3D.new()
	bolt.name = "Bolt"
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.material_override = _glow_material()
	root.add_child(bolt)
	var top := ground + Vector3(_rng.randf_range(-1.5, 1.5), height, _rng.randf_range(-1.5, 1.5))
	var view := _view_direction(parent)
	bolt.mesh = _bolt_mesh(top - ground, Vector3.ZERO, view, tint, width, 3)
	var tween := root.create_tween()
	for i in 3:
		tween.tween_interval(0.06)
		tween.tween_callback(func() -> void:
			if is_instance_valid(bolt):
				bolt.mesh = _bolt_mesh(top - ground, Vector3.ZERO, view, tint, width * (1.0 - i * 0.2), 2))
	tween.tween_property(bolt, ^"transparency", 1.0, 0.25)
	tween.tween_callback(root.queue_free)
	flash(parent, ground + Vector3.UP * 2.0, tint.lerp(Color.WHITE, 0.4), 9.0 * width, 12.0, 0.4)
	scorch(parent, ground, 2.4 * width, 3.5)
	shock_ring(parent, ground, 2.2 * width, 0.35, tint, 3.0)
	sparks(parent, ground + Vector3.UP * 0.2, tint.lerp(Color.WHITE, 0.5), 24)
	return root


## A jagged arc of electricity between two points (chain lightning), flickering briefly.
static func arc(parent: Node, from: Vector3, to: Vector3, tint: Color, width: float = 0.5) -> MeshInstance3D:
	var bolt := MeshInstance3D.new()
	bolt.name = "FxArc"
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.material_override = _glow_material()
	parent.add_child(bolt)
	bolt.global_position = from
	var view := _view_direction(parent)
	bolt.mesh = _bolt_mesh(Vector3.ZERO, to - from, view, tint, width, 1)
	var tween := bolt.create_tween()
	for i in 2:
		tween.tween_interval(0.07)
		tween.tween_callback(func() -> void:
			if is_instance_valid(bolt):
				bolt.mesh = _bolt_mesh(Vector3.ZERO, to - from, view, tint, width, 1))
	tween.tween_property(bolt, ^"transparency", 1.0, 0.2)
	tween.tween_callback(bolt.queue_free)
	return bolt


## Ribbons along a jagged line from a to b (local), facing the camera: a wide coloured glow
## and a thin white core, plus `branches` forks.
static func _bolt_mesh(a: Vector3, b: Vector3, view: Vector3, tint: Color, width: float, branches: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _jagged(a, b, maxi(int(a.distance_to(b) / 0.8), 6), 0.08)
	_ribbon(st, main, view, 0.55 * width, Color(tint, 0.35))
	_ribbon(st, main, view, 0.22 * width, Color(tint.lerp(Color.WHITE, 0.4), 0.85))
	_ribbon(st, main, view, 0.07 * width, Color(1, 1, 1, 1))
	for i in branches:
		var start_index := _rng.randi_range(1, main.size() / 2)
		var start := main[start_index]
		var toward := (b - a).normalized()
		var side := toward.cross(view).normalized() * _rng.randf_range(-1.0, 1.0)
		var end := start + (toward * _rng.randf_range(1.5, 3.5) + side * _rng.randf_range(1.0, 2.5))
		var fork := _jagged(start, end, 5, 0.1)
		_ribbon(st, fork, view, 0.25 * width, Color(tint, 0.3))
		_ribbon(st, fork, view, 0.05 * width, Color(1, 1, 1, 0.9))
	return st.commit()


static func _jagged(a: Vector3, b: Vector3, segments: int, roughness: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var length := a.distance_to(b)
	var axis := (b - a).normalized()
	var across := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := axis.cross(across).normalized()
	for i in segments + 1:
		var t := float(i) / segments
		var offset := Vector3.ZERO
		if i > 0 and i < segments:
			offset = (across * _rng.randf_range(-1, 1) + up * _rng.randf_range(-1, 1)) * length * roughness
		points.append(a.lerp(b, t) + offset)
	return points


static func _ribbon(st: SurfaceTool, points: PackedVector3Array, view: Vector3, width: float, color: Color) -> void:
	for i in points.size() - 1:
		var p := points[i]
		var q := points[i + 1]
		var side := (q - p).cross(view).normalized() * width * 0.5
		st.set_color(color)
		for v in [p - side, q - side, q + side, p - side, q + side, p + side]:
			st.add_vertex(v)


static func _glow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	return material


## The direction the active camera looks along (ribbons face it).
static func _view_direction(node: Node) -> Vector3:
	var camera := node.get_viewport().get_camera_3d() if node != null and node.is_inside_tree() else null
	return -camera.global_basis.z if camera != null else Vector3(-0.58, -0.57, -0.58).normalized()


# --- particles ------------------------------------------------------------------------

## Animated fire that keeps burning on the ground for burn seconds (the Brackeys flipbook).
static func flame_patch(parent: Node, at: Vector3, size: float, burn: float) -> CPUParticles3D:
	var fire := _flipbook_emitter(FIRE_SHEET, size, Color.WHITE, true)
	fire.color_ramp = fire_ramp()
	fire.name = "FxFlamePatch"
	fire.amount = 10
	fire.lifetime = 0.7
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = size * 0.35
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.initial_velocity_min = 0.6
	fire.initial_velocity_max = 1.4
	fire.gravity = Vector3(0, 0.8, 0)
	fire.scale_amount_min = 0.7
	fire.scale_amount_max = 1.3
	parent.add_child(fire)
	fire.global_position = at + Vector3.UP * size * 0.35
	fire.emitting = true
	var tween := fire.create_tween()
	tween.tween_interval(burn)
	tween.tween_callback(func() -> void: fire.emitting = false)
	tween.tween_interval(fire.lifetime + 0.1)
	tween.tween_callback(fire.queue_free)
	return fire


## A one-shot flipbook explosion (fireball and smoke), a ring, a burn mark and a flash.
static func explosion(parent: Node, at: Vector3, size: float, tint: Color = Color(1.0, 0.55, 0.2)) -> Node3D:
	var root := Node3D.new()
	root.name = "FxExplosion"
	parent.add_child(root)
	root.global_position = at
	var ball := _flipbook_emitter(EXPLOSION_SHEET, size, Color.WHITE, true)
	ball.name = "Fireball"
	ball.color_ramp = fire_ramp(tint)
	ball.amount = 3
	ball.lifetime = 0.75
	ball.one_shot = true
	ball.explosiveness = 0.85
	ball.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ball.emission_sphere_radius = size * 0.15
	ball.gravity = Vector3(0, 1.5, 0)
	root.add_child(ball)
	ball.position = Vector3.UP * size * 0.4
	ball.emitting = true
	var smoke := _flipbook_emitter(SMOKE_SHEET, size * 1.1, Color(0.35, 0.3, 0.28, 0.8), false)
	smoke.name = "Smoke"
	smoke.amount = 5
	smoke.lifetime = 1.3
	smoke.one_shot = true
	smoke.explosiveness = 0.6
	smoke.direction = Vector3.UP
	smoke.initial_velocity_min = 0.8
	smoke.initial_velocity_max = 1.8
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = size * 0.3
	root.add_child(smoke)
	smoke.position = Vector3.UP * size * 0.5
	smoke.emitting = true
	flash(parent, at + Vector3.UP * 1.5, tint, 7.0, size * 4.0, 0.5)
	shock_ring(parent, at, size * 1.3, 0.4, tint, 2.5)
	scorch(parent, at, size * 1.6, 4.0)
	var tween := root.create_tween()
	tween.tween_interval(1.5)
	tween.tween_callback(root.queue_free)
	return root


## Low-poly rocks thrown up from the ground around `at` that fall back (real 3D meshes,
## lit and shadowed like the world's rocks).
static func debris(parent: Node, at: Vector3, count: int, spread: float, rock_size: float = 0.22, tint: Color = Color(0.47, 0.4, 0.33)) -> CPUParticles3D:
	var rocks := CPUParticles3D.new()
	rocks.name = "FxDebris"
	rocks.amount = count
	rocks.lifetime = 1.1
	rocks.one_shot = true
	rocks.explosiveness = 0.92
	rocks.local_coords = false
	rocks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	rocks.emission_sphere_radius = spread
	rocks.direction = Vector3.UP
	rocks.spread = 40.0
	rocks.initial_velocity_min = 3.5
	rocks.initial_velocity_max = 7.0
	rocks.gravity = Vector3(0, -16.0, 0)
	rocks.angular_velocity_min = -360.0
	rocks.angular_velocity_max = 360.0
	rocks.scale_amount_min = 0.5
	rocks.scale_amount_max = 1.4
	rocks.particle_flag_rotate_y = true
	var mesh := SphereMesh.new()
	mesh.radius = rock_size
	mesh.height = rock_size * 1.5
	mesh.radial_segments = 5
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.95
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mesh.material = material
	rocks.mesh = mesh
	parent.add_child(rocks)
	rocks.global_position = at + Vector3.UP * 0.15
	rocks.emitting = true
	rocks.finished.connect(rocks.queue_free)
	return rocks


## Puffs of dust rolling outward in a ring of radius around `at`.
static func dust_ring(parent: Node, at: Vector3, radius: float, tint: Color = Color(0.72, 0.62, 0.48, 0.75)) -> CPUParticles3D:
	var dust := _flipbook_emitter(SMOKE_SHEET, 1.4, tint, false)
	dust.name = "FxDust"
	dust.amount = 18
	dust.lifetime = 1.0
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = radius
	dust.emission_ring_inner_radius = radius * 0.8
	dust.emission_ring_height = 0.1
	dust.direction = Vector3.UP
	dust.spread = 30.0
	dust.initial_velocity_min = 0.5
	dust.initial_velocity_max = 1.4
	dust.radial_accel_min = 2.0
	dust.radial_accel_max = 4.0
	dust.gravity = Vector3.ZERO
	parent.add_child(dust)
	dust.global_position = at + Vector3.UP * 0.4
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
	return dust


## A burst of bright sparks (additive dots) flying out of `at`.
static func sparks(parent: Node, at: Vector3, tint: Color, count: int = 20) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.name = "FxSparks"
	emitter.amount = count
	emitter.lifetime = 0.45
	emitter.one_shot = true
	emitter.explosiveness = 0.95
	emitter.local_coords = false
	emitter.direction = Vector3.UP
	emitter.spread = 80.0
	emitter.initial_velocity_min = 3.0
	emitter.initial_velocity_max = 7.0
	emitter.gravity = Vector3(0, -9.0, 0)
	var fade := Gradient.new()
	fade.set_color(0, Color(tint, 1.0))
	fade.set_color(1, Color(tint, 0.0))
	emitter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	var material := EnhancementGlow._additive(EnhancementGlow._texture("dot"), Color.WHITE)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	quad.material = material
	emitter.mesh = quad
	parent.add_child(emitter)
	emitter.global_position = at
	emitter.emitting = true
	emitter.finished.connect(emitter.queue_free)
	return emitter


## Colours over a flame's life for the white fire / explosion sheets: a hot yellow core,
## orange, then dark red as it fades.
static func fire_ramp(tint: Color = Color(1.0, 0.5, 0.15)) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.92, 0.55, 0.95), Color(tint, 0.9), Color(tint.r * 0.75, tint.g * 0.35, tint.b * 0.2, 0.6), Color(0.3, 0.05, 0.02, 0.0)])
	return ramp


## A particle emitter drawing an 8x8 flipbook sheet (fire / explosion: additive; smoke: mixed).
static func _flipbook_emitter(sheet: String, size: float, tint: Color, additive: bool) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.local_coords = false
	emitter.anim_speed_min = 1.0
	emitter.anim_speed_max = 1.0
	emitter.angle_min = -30.0
	emitter.angle_max = 30.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.particles_anim_h_frames = 8
	material.particles_anim_v_frames = 8
	material.particles_anim_loop = false
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = load(sheet) as Texture2D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	emitter.mesh = quad
	emitter.color = tint
	return emitter


# --- status on enemies ------------------------------------------------------------------

## An elemental status shown on a target for seconds: &"burn" (flames), &"shock" (arcs),
## &"stun" (dust and circling pebbles) or &"arcane" (violet motes). Replaces an earlier one
## of the same kind. Cosmetic only.
static func status(target: Node3D, kind: StringName, seconds: float) -> Node3D:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var node_name := "FxStatus_" + String(kind)
	var previous := target.get_node_or_null(NodePath(node_name))
	if previous != null:
		previous.free()
	var root := Node3D.new()
	root.name = node_name
	target.add_child(root)
	root.position = Vector3.UP * 0.6
	match kind:
		&"burn":
			var fire := _flipbook_emitter(FIRE_SHEET, 0.7, Color.WHITE, true)
			fire.color_ramp = fire_ramp()
			fire.amount = 6
			fire.lifetime = 0.6
			fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			fire.emission_sphere_radius = 0.35
			fire.direction = Vector3.UP
			fire.initial_velocity_min = 0.6
			fire.initial_velocity_max = 1.2
			root.add_child(fire)
			fire.emitting = true
		&"shock":
			var arcs := VfxStrip.create(&"arc_ring", 1.2, Color(0.65, 0.9, 1.0, 1.0), true)
			root.add_child(arcs)
		&"stun":
			var pivot := Node3D.new()
			pivot.position = Vector3.UP * 0.7
			root.add_child(pivot)
			for i in 3:
				var pebble := Sprite3D.new()
				pebble.texture = EnhancementGlow._texture("pebble")
				pebble.pixel_size = 0.2 / 32.0
				pebble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				pebble.modulate = Color(0.8, 0.7, 0.55)
				pebble.position = Vector3(cos(TAU * i / 3.0), 0.0, sin(TAU * i / 3.0)) * 0.4
				pivot.add_child(pebble)
			var spin := pivot.create_tween().set_loops()
			spin.tween_property(pivot, ^"rotation:y", TAU, 0.8).from(0.0)
		_:
			var motes := VfxStrip.create(&"warp", 1.1, Color(0.8, 0.6, 1.0, 1.0), true)
			root.add_child(motes)
	var tween := root.create_tween()
	tween.tween_interval(seconds)
	tween.tween_callback(root.queue_free)
	return root


# --- camera ----------------------------------------------------------------------------

## Shakes the gameplay camera (IsoCameraRig) for seconds.
static func shake(node: Node, strength: float, seconds: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	for rig in node.get_tree().get_nodes_in_group(IsoCameraRig.GROUP):
		(rig as IsoCameraRig).add_shake(strength, seconds)
