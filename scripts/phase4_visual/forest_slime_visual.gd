extends "res://scripts/phase4_visual/enemy_visual.gd"
## Forest Slime: faceted translucent jelly dome with a glowing seed core, two
## eyes and a leaf sprout. Idle breathes, move hops with squash-and-stretch,
## hit squashes away from the source, death melts into a puddle.

const BODY_HEIGHT := 0.8

var body_mesh: MeshInstance3D
var core_mesh: MeshInstance3D
var leaf_pivot: Node3D
var shadow: MeshInstance3D
var body_material: StandardMaterial3D


func _build() -> void:
	body_material = _track(Lowpoly.load_material("forest_slime_body.tres", Color(0.38, 0.74, 0.3, 0.88)))
	var core_mat := _track(Lowpoly.load_material("forest_slime_core.tres", Color(0.86, 1.0, 0.45)))
	var leaf_mat := _track(Lowpoly.load_material("forest_slime_leaf.tres", Color(0.17, 0.44, 0.15)))
	var eye_mat := Lowpoly.load_material("creature_eye.tres", Color(0.05, 0.06, 0.08))

	var shadow_mat := Lowpoly.make_material(Color(0.0, 0.0, 0.0, 0.3), 0.0, true)
	shadow = Lowpoly.add_part(self, "Shadow", Lowpoly.cone(0.5, 0.5, 0.02, 8), shadow_mat, Vector3(0, 0.01, 0), false)

	body_mesh = Lowpoly.add_part(body, "Jelly", Lowpoly.sphere(0.5, BODY_HEIGHT, 8, 4), body_material, Vector3(0, BODY_HEIGHT * 0.5, 0), false)
	core_mesh = Lowpoly.add_part(body, "SeedCore", Lowpoly.sphere(0.16, 0.24, 6, 3), core_mat, Vector3(0, 0.36, 0))
	for side in [-1.0, 1.0]:
		var eye := Lowpoly.add_part(body, "Eye%s" % ("L" if side < 0.0 else "R"), Lowpoly.box(Vector3(0.08, 0.14, 0.04)), eye_mat, Vector3(0.14 * side, 0.5, 0.42))
		eye.rotation.y = 0.25 * side

	leaf_pivot = Node3D.new()
	leaf_pivot.name = "Sprout"
	leaf_pivot.position = Vector3(0, BODY_HEIGHT - 0.04, 0)
	body.add_child(leaf_pivot)
	Lowpoly.add_part(leaf_pivot, "Stem", Lowpoly.cone(0.025, 0.02, 0.18, 4), leaf_mat, Vector3(0, 0.09, 0))
	for side in [-1.0, 1.0]:
		var leaf := Lowpoly.add_part(leaf_pivot, "Leaf", Lowpoly.prism(Vector3(0.22, 0.05, 0.12)), leaf_mat, Vector3(0.11 * side, 0.18, 0))
		leaf.rotation.z = -0.5 * side


func _apply_pose() -> void:
	if body == null or body_mesh == null:
		return
	var t := total_time
	var squash := Vector3.ONE
	var lift := 0.0
	var offset := Vector3.ZERO
	var leaf_sway := sin(t * 2.0) * 0.15
	match state:
		State.IDLE:
			var s := sin(t * 3.0) * 0.05
			squash = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
		State.MOVE:
			var phase := fmod(anim_time * 2.2, 1.0)
			var arc := sin(phase * PI)
			lift = arc * 0.35
			var land := 1.0 - smoothstep(0.0, 0.2, phase) if phase < 0.2 else 0.0
			squash = Vector3(1.0 - arc * 0.1 + land * 0.2, 1.0 + arc * 0.16 - land * 0.3, 1.0 - arc * 0.1 + land * 0.2)
			leaf_sway = -arc * 0.5
		State.HIT:
			var k := _hit_progress()
			var recoil := 1.0 - k
			squash = Vector3(1.0 + 0.3 * recoil, 1.0 - 0.4 * recoil, 1.0 + 0.3 * recoil)
			offset = knockback_dir * knockback_distance * sin(k * PI)
			leaf_sway = 0.8 * recoil
		State.DEAD:
			var d := _death_progress()
			var melt := smoothstep(0.0, 0.6, d)
			var vanish := smoothstep(0.55, 1.0, d)
			squash = Vector3(1.0 + 0.7 * melt, maxf(0.05, 1.0 - 0.92 * melt), 1.0 + 0.7 * melt) * (1.0 - vanish)
			Lowpoly.set_alpha(body_material, 0.88 * (1.0 - vanish))
			leaf_sway = 1.2 * melt
	body.scale = squash.max(Vector3(0.001, 0.001, 0.001))
	body.position = Vector3(offset.x, lift, offset.z)
	leaf_pivot.rotation.z = leaf_sway
	core_mesh.position.y = 0.36 + sin(t * 4.0) * 0.02
	var shadow_scale := (1.0 - lift * 0.8) * squash.x
	shadow.scale = Vector3(shadow_scale, 1.0, shadow_scale).max(Vector3(0.001, 1.0, 0.001))
	shadow.position = Vector3(offset.x, 0.01, offset.z)


func reset_visual() -> void:
	Lowpoly.set_alpha(body_material, 0.88)
	super.reset_visual()
