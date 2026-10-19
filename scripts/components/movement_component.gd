class_name MovementComponent
extends Node
## Reusable horizontal locomotion: acceleration, deceleration, walk/run speeds,
## and a simple movement-state classification. Owns no input and no physics body;
## the owning controller feeds it a world-space direction and applies the result.

signal state_changed(new_state: State, old_state: State)

enum State { IDLE, WALK, RUN, AIRBORNE }

@export_group("Speed")
## Phase 5H: about 11% faster than the original 4.5 m/s.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var walk_speed: float = 5.0
## Phase 5H: 12% faster than the original 7.5 m/s. The dash is separate (CombatController).
@export_range(0.5, 30.0, 0.1, "suffix:m/s") var run_speed: float = 8.4

@export_group("Animation")
## Ground speed at which the walk clip plays at 1x (the speed it was tuned for). The clip
## plays at walk_speed / walk_animation_speed, so a faster walk steps faster rather than
## sliding further per step.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var walk_animation_speed: float = 4.5
## Ground speed at which the run clip plays at 1x (see walk_animation_speed).
@export_range(0.5, 30.0, 0.1, "suffix:m/s") var run_animation_speed: float = 7.5

@export_group("Responsiveness")
## How quickly the body reaches target speed while input is held.
@export_range(1.0, 200.0, 0.5, "suffix:m/s²") var acceleration: float = 35.0
## How quickly the body stops once input is released.
@export_range(1.0, 200.0, 0.5, "suffix:m/s²") var deceleration: float = 45.0
## Multiplier applied to acceleration/deceleration while airborne.
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.35

@export_group("State")
## Horizontal speed below which the body counts as idle.
@export_range(0.0, 1.0, 0.01, "suffix:m/s") var idle_threshold: float = 0.1

var state: State = State.IDLE


## Returns the new horizontal velocity (y = 0) after one step toward the target speed.
func compute_horizontal_velocity(current_velocity: Vector3, direction: Vector3, running: bool, on_floor: bool, delta: float) -> Vector3:
	var horizontal := Vector3(current_velocity.x, 0.0, current_velocity.z)
	var has_input := direction.length_squared() > 0.0001
	var target_speed := run_speed if running else walk_speed
	var target := direction.limit_length(1.0) * target_speed if has_input else Vector3.ZERO
	var rate := acceleration if has_input else deceleration
	if not on_floor:
		rate *= air_control
	return horizontal.move_toward(target, rate * delta)


## Classifies the current movement state and emits state_changed when it changes.
func update_state(horizontal_velocity: Vector3, has_input: bool, running: bool, on_floor: bool) -> void:
	var new_state: State
	var speed := Vector2(horizontal_velocity.x, horizontal_velocity.z).length()
	if not on_floor:
		new_state = State.AIRBORNE
	elif speed < idle_threshold:
		new_state = State.IDLE
	elif running and has_input:
		new_state = State.RUN
	else:
		new_state = State.WALK
	if new_state != state:
		var old_state := state
		state = new_state
		state_changed.emit(new_state, old_state)


## Playback speed for the locomotion clip of state: target speed over the speed the clip
## was tuned for (1 for idle and airborne).
func get_animation_speed_scale(for_state: State) -> float:
	match for_state:
		State.WALK:
			return walk_speed / walk_animation_speed
		State.RUN:
			return run_speed / run_animation_speed
	return 1.0


func get_state_name() -> String:
	return State.keys()[state]
