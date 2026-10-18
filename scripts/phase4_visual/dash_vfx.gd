extends Node3D
## Dash visual: translucent courier afterimages spaced along the dash path, a
## ground wind streak and a puff ring at the arrival point. Everything fades out
## over `duration`, then the node frees itself. Purely visual.

signal finished

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")

@export var auto_animate := true
@export var duration := 0.45
@export var ghost_count := 4
@export var free_on_finish := true

var start_position := Vector3.ZERO
var end_position := Vector3.ZERO
var elapsed := 0.0
var is_finished := false
var ghosts: Array[Node3D] = []
var streak: MeshInstance3D
var puff: MeshInstance3D

var _ghost_materials: Array[StandardMaterial3D] = []
var _streak_material: StandardMaterial3D
var _puff_material: StandardMaterial3D


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


## Positions are in this node's local space (normally an effects root at the world origin).
func configure(p_start: Vector3, p_end: Vector3) -> void:
	start_position = p_start
	end_position = p_end
	_clear()
	var path := p_end - p_start
	path.y = 0.0
	var length := path.length()
	var dir := path / length if length > 0.001 else Vector3.FORWARD
	var yaw := atan2(dir.x, dir.z)

	for i in ghost_count:
		var k := float(i + 1) / float(ghost_count + 1)
		var ghost := Node3D.new()
		ghost.name = "Afterimage%d" % i
		ghost.position = p_start.lerp(p_end, k)
		ghost.rotation.y = yaw
		add_child(ghost)
		var mat := Lowpoly.load_material("dash_afterimage.tres", Color(0.45, 0.95, 1.0, 0.45))
		_ghost_materials.append(mat)
		Lowpoly.add_part(ghost, "Body", Lowpoly.capsule(0.3, 1.2, 6, 2), mat, Vector3(0, 0.6, 0), false)
		Lowpoly.add_part(ghost, "Parcel", Lowpoly.box(Vector3(0.4, 0.3, 0.3)), mat, Vector3(0, 0.75, -0.3), false)
		ghosts.append(ghost)

	_streak_material = Lowpoly.load_material("dash_afterimage.tres", Color(0.45, 0.95, 1.0, 0.45))
	streak = Lowpoly.add_part(self, "WindStreak", Lowpoly.box(Vector3(0.5, 0.02, 1.0)), _streak_material, p_start.lerp(p_end, 0.5) + Vector3(0, 0.03, 0), false)
	streak.rotation.y = yaw
	streak.scale = Vector3(1.0, 1.0, maxf(length, 0.1))

	_puff_material = Lowpoly.load_material("dash_afterimage.tres", Color(0.45, 0.95, 1.0, 0.45))
	puff = Lowpoly.add_part(self, "ArrivalPuff", Lowpoly.ring(0.3, 0.42, 10), _puff_material, p_end + Vector3(0, 0.1, 0), false)
	elapsed = 0.0
	is_finished = false
	_apply(0.0)


func advance(delta: float) -> void:
	if is_finished:
		return
	elapsed += delta
	var k := clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	_apply(k)
	if k >= 1.0:
		is_finished = true
		finished.emit()
		if free_on_finish:
			queue_free()


func get_ghost_alpha(index: int) -> float:
	if index < 0 or index >= _ghost_materials.size():
		return 0.0
	return _ghost_materials[index].albedo_color.a


func _apply(k: float) -> void:
	for i in _ghost_materials.size():
		# Older afterimages (closer to the start) fade first.
		var age := float(ghost_count - i) / float(ghost_count)
		var fade := clampf(1.0 - k * (1.0 + age * 0.5), 0.0, 1.0)
		Lowpoly.set_alpha(_ghost_materials[i], 0.45 * fade)
		ghosts[i].scale = Vector3.ONE * (1.0 - 0.2 * k)
	if _streak_material != null:
		Lowpoly.set_alpha(_streak_material, 0.35 * (1.0 - k))
	if puff != null:
		puff.scale = Vector3.ONE * lerpf(0.4, 1.8, k)
		Lowpoly.set_alpha(_puff_material, 0.5 * (1.0 - k))


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	ghosts.clear()
	_ghost_materials.clear()
	streak = null
	puff = null
