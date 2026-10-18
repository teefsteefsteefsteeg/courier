class_name FrostWisp
extends Enemy
## Hovering ranged caster. Keeps roughly preferred_distance from the courier, RETREATs
## when crowded, and in range winds up (WINDUP, attack_telegraphed) before firing a
## Frost Shard at the position the target had when the windup began, so moving during
## the tell dodges it. Shards hit the world and the player layer only.

signal attack_telegraphed(aim_position: Vector3)
signal shard_fired(origin: Vector3, direction: Vector3)

const FROST_SHARD_SCENE := preload("res://scenes/gameplay/combat/frost_shard.tscn")

@export_group("Positioning")
@export_range(0.0, 50.0, 0.1, "suffix:m") var preferred_distance: float = 6.0
## Closer than this the wisp backs off until it is at preferred_distance again.
@export_range(0.0, 50.0, 0.1, "suffix:m") var retreat_distance: float = 3.5
## Height of the wisp's core above its origin; shards are fired from here.
@export var hover_height: float = 1.1

@export_group("Attack")
## Scene whose root is a CombatProjectile. Defaults to the Phase 4 frost shard.
@export var frost_shard_scene: PackedScene
@export var shard_damage: float = 12.0
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var shard_speed: float = 10.0
@export_range(0.1, 100.0, 0.1, "suffix:m") var shard_range: float = 14.0
@export_range(0.1, 50.0, 0.1, "suffix:m") var attack_range: float = 9.0
@export_range(0.0, 5.0, 0.05, "suffix:s") var attack_windup: float = 0.6
@export_range(0.0, 10.0, 0.05, "suffix:s") var attack_cooldown: float = 2.2
## Height above the target's origin the shard aims at (torso).
@export var aim_height: float = 0.8
@export_flags_3d_physics var shard_collision_mask: int = CombatController.WORLD_LAYER | CombatController.PLAYER_LAYER

var _aim_position: Vector3 = Vector3.ZERO


func _init() -> void:
	use_gravity = false
	detection_radius = 11.0
	lose_interest_radius = 16.0
	move_speed = 2.2


func _update_behaviour(_delta: float, current_target: Node3D) -> Vector3:
	match state:
		State.IDLE:
			if should_engage(current_target):
				set_state(State.CHASE)
			return Vector3.ZERO
		State.CHASE:
			if should_disengage(current_target):
				set_state(State.IDLE)
				return Vector3.ZERO
			var distance := horizontal_distance_to(current_target)
			var toward := horizontal_direction_to(current_target)
			if distance < retreat_distance:
				set_state(State.RETREAT)
				return -toward * move_speed
			if distance <= attack_range and _attack_cooldown_left <= 0.0:
				_aim_position = current_target.global_position + Vector3.UP * aim_height
				set_state(State.WINDUP)
				attack_telegraphed.emit(_aim_position)
				return Vector3.ZERO
			if distance > preferred_distance + 0.5:
				return toward * move_speed
			if distance < preferred_distance - 0.5:
				return -toward * move_speed
			return Vector3.ZERO
		State.RETREAT:
			if should_disengage(current_target):
				set_state(State.IDLE)
				return Vector3.ZERO
			if horizontal_distance_to(current_target) >= preferred_distance:
				set_state(State.CHASE)
				return Vector3.ZERO
			return -horizontal_direction_to(current_target) * move_speed
		State.WINDUP:
			if state_time >= attack_windup:
				fire_shard(_aim_position)
				_attack_cooldown_left = attack_cooldown
				set_state(State.CHASE)
			return Vector3.ZERO
	return Vector3.ZERO


func get_shard_origin() -> Vector3:
	return global_position + Vector3.UP * hover_height


## Spawns a Frost Shard flying from the wisp's core toward aim_position.
func fire_shard(aim_position: Vector3) -> CombatProjectile:
	if not is_inside_tree() or get_parent() == null:
		return null
	var origin := get_shard_origin()
	var direction := aim_position - origin
	if direction.length_squared() < 0.0001:
		direction = -global_basis.z
	direction = direction.normalized()
	var scene := frost_shard_scene if frost_shard_scene != null else FROST_SHARD_SCENE
	var shard := scene.instantiate() as CombatProjectile
	shard.damage = shard_damage
	shard.speed = shard_speed
	shard.max_distance = shard_range
	shard.collision_mask = shard_collision_mask
	shard.direction = direction
	shard.source = self
	get_parent().add_child(shard)
	shard.global_position = origin
	shard.reset_physics_interpolation()
	shard_fired.emit(origin, direction)
	return shard
