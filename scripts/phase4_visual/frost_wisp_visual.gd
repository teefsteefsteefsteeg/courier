extends "res://scripts/phase4_visual/enemy_visual.gd"
## Frost Wisp: glowing faceted ice core inside a translucent shell, a tapering
## frost tail and orbiting ice shards. Idle hovers and bobs, move leans into the
## travel direction with a faster orbit, hit flickers and scatters shards, death
## shatters the shards outward while the core collapses and drops.

const SHARD_COUNT := 4
const HOVER_HEIGHT := 1.15
const ORBIT_RADIUS := 0.55

var core_mesh: MeshInstance3D
var shell_mesh: MeshInstance3D
var tail_mesh: MeshInstance3D
var glow: OmniLight3D
var shards: Array[MeshInstance3D] = []
var shell_material: StandardMaterial3D
var shard_material: StandardMaterial3D
var _orbit_angle := 0.0


func _build() -> void:
	var core_mat := _track(Lowpoly.load_material("frost_wisp_core.tres", Color(0.86, 0.97, 1.0)))
	shell_material = _track(Lowpoly.load_material("frost_wisp_shell.tres", Color(0.55, 0.82, 1.0, 0.42)))
	shard_material = _track(Lowpoly.load_material("frost_wisp_shard.tres", Color(0.76, 0.93, 1.0)))

	core_mesh = Lowpoly.add_part(body, "Core", Lowpoly.sphere(0.2, 0.4, 6, 3), core_mat)
	shell_mesh = Lowpoly.add_part(body, "Shell", Lowpoly.sphere(0.36, 0.72, 5, 3), shell_material, Vector3.ZERO, false)
	tail_mesh = Lowpoly.add_part(body, "Tail", Lowpoly.cone(0.0, 0.22, 0.6, 5), shell_material, Vector3(0, -0.42, 0), false)
	for i in SHARD_COUNT:
		var shard := Lowpoly.add_part(body, "Shard%d" % i, Lowpoly.prism(Vector3(0.1, 0.26, 0.08)), shard_material)
		shards.append(shard)

	glow = OmniLight3D.new()
	glow.name = "FrostGlow"
	glow.light_color = Color(0.55, 0.82, 1.0)
	glow.light_energy = 0.8
	glow.omni_range = 2.5
	body.add_child(glow)

	var shadow_mat := Lowpoly.make_material(Color(0.1, 0.2, 0.35, 0.25), 0.0, true)
	Lowpoly.add_part(self, "Shadow", Lowpoly.cone(0.35, 0.35, 0.02, 8), shadow_mat, Vector3(0, 0.01, 0), false)


func _apply_pose() -> void:
	if body == null or core_mesh == null:
		return
	var t := total_time
	var bob := sin(t * 2.0) * 0.12
	var orbit_speed := 1.5
	var orbit_radius := ORBIT_RADIUS
	var lean := 0.0
	var offset := Vector3.ZERO
	var core_scale := 1.0 + sin(t * 5.0) * 0.06
	var shard_alpha := 1.0
	var drop := 0.0
	var tail_stretch := 1.0
	var spin := 0.0
	match state:
		State.MOVE:
			orbit_speed = 3.2
			lean = -0.35
			tail_stretch = 1.4
			bob *= 0.5
		State.HIT:
			var k := _hit_progress()
			var recoil := 1.0 - k
			orbit_radius = ORBIT_RADIUS * (1.0 + 0.6 * recoil)
			offset = knockback_dir * knockback_distance * sin(k * PI)
			offset += Vector3(sin(t * 60.0), 0.0, cos(t * 53.0)) * 0.04 * recoil
			core_scale = 1.0 + 0.35 * recoil
		State.DEAD:
			var d := _death_progress()
			orbit_radius = ORBIT_RADIUS * (1.0 + 3.0 * d)
			orbit_speed = 0.5
			shard_alpha = 1.0 - d
			core_scale = maxf(0.001, 1.0 - d)
			drop = d * d * HOVER_HEIGHT * 0.8
			spin = d * TAU
			Lowpoly.set_alpha(shell_material, 0.42 * (1.0 - d))
			glow.light_energy = 0.8 * (1.0 - d)
	if state != State.DEAD:
		_orbit_angle = t * orbit_speed
	body.position = Vector3(offset.x, HOVER_HEIGHT + bob - drop, offset.z)
	body.rotation = Vector3(lean, spin, 0.0)
	core_mesh.scale = Vector3.ONE * core_scale
	shell_mesh.scale = Vector3.ONE * (0.95 + 0.05 * sin(t * 3.0)) * maxf(core_scale, 0.001)
	tail_mesh.scale = Vector3(1.0, tail_stretch, 1.0) * maxf(core_scale, 0.001)
	tail_mesh.rotation.y = t * 1.3
	Lowpoly.set_alpha(shard_material, shard_alpha)
	for i in shards.size():
		var a := _orbit_angle + TAU * float(i) / float(shards.size())
		var shard := shards[i]
		shard.position = Vector3(cos(a) * orbit_radius, sin(t * 3.0 + float(i)) * 0.08, sin(a) * orbit_radius)
		shard.rotation = Vector3(0.3, -a, t * 2.0 + float(i))


func get_orbit_radius() -> float:
	if shards.is_empty():
		return 0.0
	var p := shards[0].position
	return Vector2(p.x, p.z).length()


func reset_visual() -> void:
	Lowpoly.set_alpha(shell_material, 0.42)
	Lowpoly.set_alpha(shard_material, 1.0)
	if glow != null:
		glow.light_energy = 0.8
	super.reset_visual()
