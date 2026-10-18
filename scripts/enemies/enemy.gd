class_name Enemy
extends CharacterBody3D
## Base for hostile creatures. Owns a CombatHealth child, targets the courier (any body
## in CombatController.PLAYER_GROUP unless target is set), and runs a small state machine
## in advance(delta). Subclasses implement _update_behaviour() and return the horizontal
## velocity they want this step.
##
## advance() runs every physics frame while simulate is on; tests may disable that and
## step it with a fixed delta (1/60) for deterministic results.

signal state_changed(new_state: State, old_state: State)
## An attack resolved against target. landed is false if it missed or was negated.
signal attacked(target: Node3D, landed: bool)
## Emitted once when health reaches 0, before the body is freed.
signal defeated(enemy: Enemy)

enum State { IDLE, CHASE, WINDUP, RECOVER, RETREAT, DEAD }

@export var health: CombatHealth
## Explicit target. When empty, the first node in CombatController.PLAYER_GROUP is used.
@export var target: Node3D
@export_range(0.0, 100.0, 0.1, "suffix:m") var detection_radius: float = 8.0
## A chasing enemy that was not provoked gives up beyond this distance.
@export_range(0.0, 200.0, 0.1, "suffix:m") var lose_interest_radius: float = 14.0
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var move_speed: float = 2.5
@export var use_gravity: bool = true
@export var simulate: bool = true
@export var free_on_death: bool = true
## Seconds the defeated body lingers (for death effects) before it is freed.
@export_range(0.0, 10.0, 0.05, "suffix:s") var death_free_delay: float = 0.6

var state: State = State.IDLE
## Seconds spent in the current state.
var state_time: float = 0.0
## Set when damaged: the enemy engages regardless of detection/lose-interest radii.
var provoked: bool = false

var _attack_cooldown_left: float = 0.0


func _ready() -> void:
	collision_layer = CombatController.ENEMY_LAYER
	collision_mask = CombatController.WORLD_LAYER
	if health == null:
		health = CombatHealth.find_on(self)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if simulate:
		advance(delta)


func advance(delta: float) -> void:
	if delta <= 0.0 or state == State.DEAD:
		return
	state_time += delta
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	var desired := _update_behaviour(delta, find_target())
	_move(desired, delta)


## Override: decide state transitions and return the desired horizontal velocity.
func _update_behaviour(_delta: float, _current_target: Node3D) -> Vector3:
	return Vector3.ZERO


func find_target() -> Node3D:
	if target != null and is_instance_valid(target):
		return target
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as Node3D


## True if the candidate exists and is not dead.
func is_target_alive(candidate: Node3D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	var target_health := CombatHealth.find_on(candidate)
	return target_health == null or not target_health.is_dead()


func is_dead() -> bool:
	return state == State.DEAD


func get_state_name() -> String:
	return State.keys()[state]


func get_attack_cooldown_remaining() -> float:
	return _attack_cooldown_left


func horizontal_distance_to(node: Node3D) -> float:
	var offset := node.global_position - global_position
	return Vector2(offset.x, offset.z).length()


## Flat unit vector toward node (zero if on top of it).
func horizontal_direction_to(node: Node3D) -> Vector3:
	var offset := node.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	return offset.normalized()


## True if an idle enemy should start engaging candidate.
func should_engage(candidate: Node3D) -> bool:
	if not is_target_alive(candidate):
		return false
	return provoked or horizontal_distance_to(candidate) <= detection_radius


## True if an engaged enemy should give up on candidate.
func should_disengage(candidate: Node3D) -> bool:
	if not is_target_alive(candidate):
		return true
	return not provoked and horizontal_distance_to(candidate) > lose_interest_radius


func set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_time = 0.0
	state_changed.emit(new_state, old)


## Applies damage to candidate's CombatHealth and emits attacked. Returns true if it landed.
func strike(candidate: Node3D, amount: float) -> bool:
	var target_health := CombatHealth.find_on(candidate)
	var landed := target_health != null and target_health.apply_damage(amount, global_position)
	attacked.emit(candidate, landed)
	return landed


func _move(desired: Vector3, delta: float) -> void:
	velocity.x = desired.x
	velocity.z = desired.z
	if use_gravity and is_inside_tree() and not is_on_floor():
		velocity += get_gravity() * delta
	elif not use_gravity or is_on_floor():
		velocity.y = 0.0
	if desired.length_squared() > 0.0001:
		rotation.y = FacingComponent.yaw_for_direction(desired)
	if is_inside_tree():
		move_and_slide()


func _on_damaged(_amount: float, _source_position: Vector3) -> void:
	provoked = true


func _on_died() -> void:
	set_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	defeated.emit(self)
	if not free_on_death or not is_inside_tree():
		return
	if death_free_delay <= 0.0:
		queue_free()
	else:
		get_tree().create_timer(death_free_delay, false, true).timeout.connect(queue_free)
