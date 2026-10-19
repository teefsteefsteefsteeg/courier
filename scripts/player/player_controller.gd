class_name PlayerController
extends CharacterBody3D
## Courier player: reads input, converts it to a camera-relative world direction,
## and delegates locomotion, facing, and interaction to child components.
## Phase 8: jumps on `jump` (Ctrl) from the ground only (no double jump), with a short
## coyote time after walking off an edge and a short buffer for a press just before landing.

## Left the ground by a jump.
signal jumped
## Touched down after a jump, or after a fall of at least LANDING_MIN_AIR seconds.
signal landed(air_time: float)

const LANDING_MIN_AIR := 0.25

@export var movement: MovementComponent
@export var facing: FacingComponent
@export var interaction: InteractionDetector
## Optional node whose yaw defines "forward". Defaults to the viewport's active camera.
@export var movement_reference: Node3D

## Take-off speed: 4.8 m/s rises about 1.2 m at the default gravity (9.8 m/s²).
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var jump_velocity: float = 4.8
## A jump is still allowed this long after leaving the ground without jumping.
@export_range(0.0, 0.5, 0.01, "suffix:s") var coyote_time: float = 0.1
## A press this long before touching down jumps on landing.
@export_range(0.0, 0.5, 0.01, "suffix:s") var jump_buffer: float = 0.12

var input_enabled: bool = true
## World-space (XZ) direction requested this physics frame. Length 0..1.
var move_direction: Vector3 = Vector3.ZERO
var _since_floor: float = 0.0
var _buffered_jump: float = -1.0
var _jumping := false
var _air_time: float = 0.0


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	var running := false
	if input_enabled:
		input_vector = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		running = Input.is_action_pressed(&"run")
	move_direction = camera_relative_direction(input_vector)

	var on_floor := is_on_floor()
	_since_floor = 0.0 if on_floor else _since_floor + delta
	if _buffered_jump >= 0.0:
		_buffered_jump -= delta
		if _buffered_jump >= 0.0 and input_enabled and not _jumping and _since_floor <= coyote_time:
			_buffered_jump = -1.0
			_jumping = true
			velocity.y = jump_velocity
			on_floor = false
			jumped.emit()
	if not on_floor:
		velocity += get_gravity() * delta
	var horizontal := movement.compute_horizontal_velocity(velocity, move_direction, running, on_floor, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	var has_input := move_direction.length_squared() > 0.0001
	if is_on_floor():
		if _jumping or _air_time >= LANDING_MIN_AIR:
			landed.emit(_air_time)
		_jumping = false
		_air_time = 0.0
	else:
		_air_time += delta
	movement.update_state(velocity, has_input, running, is_on_floor())
	facing.update_facing(move_direction, delta)


func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed(&"jump"):
		request_jump()
		get_viewport().set_input_as_handled()
	elif input_enabled and event.is_action_pressed(&"interact"):
		if interaction.try_interact(self):
			get_viewport().set_input_as_handled()


## Maps a 2D input vector (x = right, y = back) onto the ground plane using
## only the reference node's yaw, so camera position/follow never alters direction.
func camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector == Vector2.ZERO:
		return Vector3.ZERO
	var reference: Node3D = movement_reference if movement_reference != null else get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var back := Vector3.BACK
	if reference != null:
		var ref_basis := reference.global_basis
		right = Vector3(ref_basis.x.x, 0.0, ref_basis.x.z).normalized()
		back = Vector3(ref_basis.z.x, 0.0, ref_basis.z.z).normalized()
	return (right * input_vector.x + back * input_vector.y).limit_length(1.0)


## Jumps at the next physics step if the courier is on the ground (or just left it), or
## when it lands within jump_buffer seconds. Mid-air presses never jump twice.
func request_jump() -> void:
	_buffered_jump = jump_buffer


func is_jumping() -> bool:
	return _jumping


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Moves the player instantly (spawns, tests) without interpolation smearing.
func teleport_to(world_position: Vector3) -> void:
	global_position = world_position
	velocity = Vector3.ZERO
	_jumping = false
	_buffered_jump = -1.0
	_air_time = 0.0
	reset_physics_interpolation()
