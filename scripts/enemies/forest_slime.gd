class_name ForestSlime
extends Enemy
## Melee chaser. Creeps toward the courier once within detection_radius; when close it
## winds up (WINDUP, a visible tell) and then strikes anything still within
## attack_range + attack_reach_grace. Stepping or dashing away during the windup avoids
## the hit. After a strike it RECOVERs for attack_cooldown before chasing again.

@export_group("Attack")
@export var contact_damage: float = 10.0
@export_range(0.1, 10.0, 0.05, "suffix:m") var attack_range: float = 1.2
@export_range(0.0, 5.0, 0.05, "suffix:m") var attack_reach_grace: float = 0.3
@export_range(0.0, 5.0, 0.05, "suffix:s") var attack_windup: float = 0.35
@export_range(0.0, 10.0, 0.05, "suffix:s") var attack_cooldown: float = 1.0


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
			if horizontal_distance_to(current_target) <= attack_range:
				set_state(State.WINDUP)
				return Vector3.ZERO
			return horizontal_direction_to(current_target) * move_speed
		State.WINDUP:
			if state_time >= attack_windup:
				if is_target_alive(current_target) and horizontal_distance_to(current_target) <= attack_range + attack_reach_grace:
					strike(current_target, contact_damage)
				else:
					attacked.emit(current_target, false)
				_attack_cooldown_left = attack_cooldown
				set_state(State.RECOVER)
			return Vector3.ZERO
		State.RECOVER:
			if _attack_cooldown_left <= 0.0:
				set_state(State.CHASE)
			return Vector3.ZERO
	return Vector3.ZERO
