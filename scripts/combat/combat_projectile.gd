class_name CombatProjectile
extends Node3D
## Straight-line projectile (Magic Bolt, Frost Shard). Each step ray-casts from the old
## to the new position, so fast projectiles never tunnel through thin geometry. The first
## body hit consumes it: bodies with a CombatHealth take damage, anything else (walls,
## props) just stops it. The shooter (source) is always ignored.

## Damage landed on target (the body that was hit). amount is what got through.
signal hit(target: Node, amount: float)
## The projectile ended. reason: &"hit", &"blocked" (no damage dealt) or &"range".
signal expired(reason: StringName)

const REASON_HIT := &"hit"
const REASON_BLOCKED := &"blocked"
const REASON_RANGE := &"range"

@export var damage: float = 20.0
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var speed: float = 18.0
@export_range(0.1, 100.0, 0.1, "suffix:m") var max_distance: float = 18.0
@export_flags_3d_physics var collision_mask: int = 1
## Move every physics frame. Tests may disable this and call advance() directly.
@export var simulate: bool = true
## Adds a small glowing sphere when the scene provides no visual of its own.
@export var build_placeholder_visual: bool = true
@export var placeholder_color: Color = Color(0.55, 0.75, 1.0)

## Normalized travel direction.
var direction: Vector3 = Vector3.FORWARD
## Node that fired the projectile; never hit.
var source: Node = null
var traveled: float = 0.0

var _done: bool = false


func _ready() -> void:
	if build_placeholder_visual and get_child_count() == 0:
		var mesh := SphereMesh.new()
		mesh.radius = 0.15
		mesh.height = 0.3
		var material := StandardMaterial3D.new()
		material.albedo_color = placeholder_color
		material.emission_enabled = true
		material.emission = placeholder_color
		mesh.material = material
		var visual := MeshInstance3D.new()
		visual.name = "PlaceholderVisual"
		visual.mesh = mesh
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)


func _physics_process(delta: float) -> void:
	if simulate:
		advance(delta)


func is_finished() -> bool:
	return _done


## Moves the projectile by speed * delta (capped at max_distance) and resolves hits.
func advance(delta: float) -> void:
	if _done or delta <= 0.0:
		return
	var step := minf(speed * delta, max_distance - traveled)
	var from := global_position
	var to := from + direction * step
	var result := _cast(from, to)
	if not result.is_empty():
		global_position = result.position
		traveled += from.distance_to(global_position)
		_impact(result.collider)
		return
	global_position = to
	traveled += step
	if traveled >= max_distance - 0.0001:
		_finish(REASON_RANGE)


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var exclude: Array[RID] = []
	if is_instance_valid(source) and source is CollisionObject3D:
		exclude.append((source as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _impact(collider: Object) -> void:
	var target := collider as Node
	var health := CombatHealth.find_on(target)
	if health != null and health.apply_damage(damage, global_position):
		hit.emit(target, health.last_damage_taken)
		_finish(REASON_HIT)
	else:
		_finish(REASON_BLOCKED)


func _finish(reason: StringName) -> void:
	if _done:
		return
	_done = true
	expired.emit(reason)
	queue_free()
