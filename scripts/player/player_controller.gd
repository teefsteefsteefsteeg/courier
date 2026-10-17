class_name PlayerController
extends CharacterBody3D
## Courier player: reads input, converts it to a camera-relative world direction,
## and delegates locomotion, facing, and interaction to child components.

@export var movement: MovementComponent
@export var facing: FacingComponent
@export var interaction: InteractionDetector
## Optional node whose yaw defines "forward". Defaults to the viewport's active camera.
@export var movement_reference: Node3D

var input_enabled: bool = true
## World-space (XZ) direction requested this physics frame. Length 0..1.
var move_direction: Vector3 = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var input_vector := Vector2.ZERO
	var running := false
	if input_enabled:
		input_vector = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		running = Input.is_action_pressed(&"run")
	move_direction = camera_relative_direction(input_vector)

	if not is_on_floor():
		velocity += get_gravity() * delta
	var horizontal := movement.compute_horizontal_velocity(velocity, move_direction, running, is_on_floor(), delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	var has_input := move_direction.length_squared() > 0.0001
	movement.update_state(velocity, has_input, running, is_on_floor())
	facing.update_facing(move_direction, delta)


func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event.is_action_pressed(&"interact"):
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


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Moves the player instantly (spawns, tests) without interpolation smearing.
func teleport_to(world_position: Vector3) -> void:
	global_position = world_position
	velocity = Vector3.ZERO
	reset_physics_interpolation()
