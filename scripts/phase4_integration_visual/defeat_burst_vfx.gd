extends Node3D
## Enemy defeat burst: an expanding ground ring in the enemy's tint plus a
## fountain of faceted petals (pink, gold, lime, sky) that arc up and fade,
## then the node frees itself. Purely visual. Position is local to its parent
## (normally the combat layer's Effects root).

signal finished

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const Assets := preload("res://scripts/phase4_integration_visual/integration_assets.gd")
const PETAL_COLORS := [
	Color(1.0, 0.5, 0.75), Color(1.0, 0.88, 0.35), Color(0.6, 1.0, 0.45), Color(0.55, 0.85, 1.0),
]
const GRAVITY := 9.0

@export var auto_animate := true
@export var duration := 0.75
@export var petal_count := 8
@export var ring_radius := 1.3

var tint := Color(0.6, 1.0, 0.4)
var elapsed := 0.0
var ring: MeshInstance3D
var ring_material: StandardMaterial3D
var petals: Array[MeshInstance3D] = []
var petal_velocities: Array[Vector3] = []

var _petal_materials: Array[StandardMaterial3D] = []
var _finished := false


func _ready() -> void:
	_ensure_built()
	_apply()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


func configure(local_position: Vector3, p_tint := Color(0.6, 1.0, 0.4)) -> void:
	_ensure_built()
	position = local_position
	tint = p_tint
	elapsed = 0.0
	_apply()


func advance(delta: float) -> void:
	if _finished:
		return
	elapsed += delta
	_apply()
	if elapsed >= duration:
		_finished = true
		finished.emit()
		queue_free()


func get_progress() -> float:
	return clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)


func _apply() -> void:
	if ring == null:
		return
	var k := get_progress()
	ring.scale = Vector3.ONE * maxf(0.001, lerpf(0.2, 1.0, 1.0 - (1.0 - k) * (1.0 - k)))
	var rc := tint
	rc.a = 0.9 * (1.0 - k)
	ring_material.albedo_color = rc
	var t := k * duration
	for i in petals.size():
		var v := petal_velocities[i]
		petals[i].position = Vector3(v.x * t, 0.4 + v.y * t - 0.5 * GRAVITY * t * t, v.z * t)
		petals[i].rotation = Vector3(t * 7.0 + float(i), t * 5.0, 0.0)
		petals[i].scale = Vector3.ONE * maxf(0.001, 1.0 - k * 0.8)
	for mat in _petal_materials:
		Lowpoly.set_alpha(mat, 1.0 - k * k)


func _ensure_built() -> void:
	if ring != null:
		return
	ring_material = Assets.load_material("defeat_burst.tres", Color(0.6, 1.0, 0.4, 0.9))
	ring = Lowpoly.add_part(self, "Ring", Lowpoly.ring(ring_radius * 0.85, ring_radius, 14), ring_material, Vector3(0, 0.08, 0), false)
	for c in PETAL_COLORS:
		var mat := Lowpoly.make_material(c, 1.2, true)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_petal_materials.append(mat)
	var mesh := Lowpoly.prism(Vector3(0.14, 0.2, 0.05))
	for i in petal_count:
		var a := TAU * float(i) / float(maxi(petal_count, 1))
		var petal := Lowpoly.add_part(self, "Petal%d" % i, mesh, _petal_materials[i % _petal_materials.size()], Vector3(0, 0.4, 0), false)
		petals.append(petal)
		petal_velocities.append(Vector3(cos(a) * 2.2, 2.6 + 0.6 * sin(a * 3.0), sin(a) * 2.2))
