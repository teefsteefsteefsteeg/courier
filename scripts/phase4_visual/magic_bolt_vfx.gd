extends Node3D
## Magic bolt projectile visual: spinning faceted core with an additive glow,
## a fading trail and an expanding ring + spark burst on impact.
## Purely visual: it never applies damage. Positions are in this node's local
## space (normally an effects root at the world origin).

signal impacted(world_position: Vector3)
signal finished

const Lowpoly := preload("res://scripts/phase4_visual/lowpoly.gd")
const TRAIL_COUNT := 6
const SPARK_COUNT := 6

@export var auto_animate := true
@export var speed := 16.0
@export var max_distance := 12.0
@export var burst_duration := 0.35
@export var free_on_finish := true

var origin := Vector3.ZERO
var direction := Vector3.FORWARD
var traveled := 0.0
var has_impacted := false
var is_finished := false
var burst_time := 0.0
var head: Node3D
var burst: Node3D
var trail: Array[MeshInstance3D] = []
var sparks: Array[MeshInstance3D] = []

var _history: Array[Vector3] = []
var _trail_materials: Array[StandardMaterial3D] = []
var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _spark_material: StandardMaterial3D


func _ready() -> void:
	_ensure_built()


func _process(delta: float) -> void:
	if auto_animate:
		advance(delta)


func configure(p_origin: Vector3, p_direction: Vector3, p_max_distance := -1.0) -> void:
	_ensure_built()
	origin = p_origin
	direction = p_direction.normalized() if p_direction.length_squared() > 0.0001 else Vector3.FORWARD
	if p_max_distance > 0.0:
		max_distance = p_max_distance
	traveled = 0.0
	head.position = origin
	_history.clear()
	for i in TRAIL_COUNT:
		_history.append(origin)
	_update_trail()


func advance(delta: float) -> void:
	if is_finished:
		return
	if not has_impacted:
		var step := minf(speed * delta, max_distance - traveled)
		traveled += step
		head.position = origin + direction * traveled
		head.rotate_object_local(Vector3.FORWARD, delta * 12.0)
		_history.push_front(head.position)
		_history.resize(TRAIL_COUNT)
		_update_trail()
		if traveled >= max_distance - 0.0001:
			impact()
	else:
		burst_time += delta
		var k := clampf(burst_time / maxf(burst_duration, 0.001), 0.0, 1.0)
		_ring.scale = Vector3.ONE * lerpf(0.2, 1.6, k)
		Lowpoly.set_alpha(_ring_material, 1.0 - k)
		Lowpoly.set_alpha(_spark_material, 1.0 - k)
		for i in sparks.size():
			var a := TAU * float(i) / float(sparks.size())
			sparks[i].position = Vector3(cos(a), 0.4 + 0.6 * sin(float(i) * 1.7), sin(a)) * k * 0.9
		for i in trail.size():
			Lowpoly.set_alpha(_trail_materials[i], (1.0 - k) * _trail_alpha(i) * 0.5)
		if k >= 1.0:
			is_finished = true
			finished.emit()
			if free_on_finish:
				queue_free()


## Ends flight early (e.g. when gameplay reports target_hit). local_position is
## optional and in this node's local space.
func impact(local_position: Vector3 = Vector3.INF) -> void:
	if has_impacted:
		return
	_ensure_built()
	if local_position.is_finite():
		head.position = local_position
	has_impacted = true
	head.visible = false
	burst.position = head.position
	burst.visible = true
	impacted.emit(get_head_world_position())


func get_head_position() -> Vector3:
	return head.position


func get_head_world_position() -> Vector3:
	return head.global_position if head.is_inside_tree() else head.position


func _trail_alpha(i: int) -> float:
	return 0.7 * (1.0 - float(i) / float(TRAIL_COUNT))


func _update_trail() -> void:
	for i in trail.size():
		trail[i].position = _history[mini(i, _history.size() - 1)]
		Lowpoly.set_alpha(_trail_materials[i], _trail_alpha(i))


func _ensure_built() -> void:
	if head != null:
		return
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	var core_mat := Lowpoly.load_material("magic_bolt.tres", Color(0.8, 0.58, 1.0))
	var glow_mat := Lowpoly.load_material("magic_bolt_glow.tres", Color(0.55, 0.35, 1.0, 0.5))
	Lowpoly.add_part(head, "Core", Lowpoly.sphere(0.12, 0.24, 6, 3), core_mat, Vector3.ZERO, false)
	Lowpoly.add_part(head, "Glow", Lowpoly.sphere(0.24, 0.48, 6, 3), glow_mat, Vector3.ZERO, false)
	var spike := Lowpoly.add_part(head, "Spike", Lowpoly.prism(Vector3(0.12, 0.4, 0.12)), core_mat, Vector3(0, 0, 0.15), false)
	spike.rotation.x = -PI * 0.5

	var trail_root := Node3D.new()
	trail_root.name = "Trail"
	add_child(trail_root)
	for i in TRAIL_COUNT:
		var mat := Lowpoly.load_material("magic_bolt_glow.tres", Color(0.55, 0.35, 1.0, 0.5))
		_trail_materials.append(mat)
		var size := 0.16 * (1.0 - float(i) / float(TRAIL_COUNT + 1))
		trail.append(Lowpoly.add_part(trail_root, "Trail%d" % i, Lowpoly.sphere(size, size * 2.0, 5, 2), mat, Vector3.ZERO, false))

	burst = Node3D.new()
	burst.name = "ImpactBurst"
	burst.visible = false
	add_child(burst)
	_ring_material = Lowpoly.load_material("impact_spark.tres", Color(1.0, 0.86, 0.55))
	_ring = Lowpoly.add_part(burst, "Ring", Lowpoly.ring(0.35, 0.45, 10), _ring_material, Vector3.ZERO, false)
	_spark_material = Lowpoly.load_material("impact_spark.tres", Color(1.0, 0.86, 0.55))
	for i in SPARK_COUNT:
		sparks.append(Lowpoly.add_part(burst, "Spark%d" % i, Lowpoly.prism(Vector3(0.06, 0.16, 0.06)), _spark_material, Vector3.ZERO, false))
	_history.clear()
	for i in TRAIL_COUNT:
		_history.append(origin)
