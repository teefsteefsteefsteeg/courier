class_name CombatController
extends Node
## Courier combat abilities, added as the "Combat" child of a CharacterBody3D:
## - Magic Bolt: ranged projectile along the aim direction, on a cooldown.
## - Dash: short burst of movement; the body takes no damage while dashing.
## - Package Shield: while a package is carried, absorbs incoming damage until its
##   durability runs out. It cannot be raised without a package and drops automatically
##   when the package leaves the carrier.
##
## Damage rules (deterministic, applied in this order through CombatHealth):
## 1. While dashing (dash_invulnerable), all damage is negated.
## 2. While the shield is up, it absorbs min(damage, durability); the rest goes through.
##    Reaching 0 durability breaks the shield (shield_broken).
## 3. Damage that reaches health while carrying a package also applies
##    damage * package_impact_per_damage impact to the package. Absorbed damage does not.
##
## Timers only advance in advance(delta), called each physics frame while simulate is on,
## so tests can drive the controller with exact deltas.

signal magic_bolt_fired(origin: Vector3, direction: Vector3)
signal dash_started
signal dash_finished
## Emitted when the shield is raised/lowered/broken and whenever its durability changes.
signal shield_changed(active: bool, durability: float)
## A Magic Bolt damaged target (the body hit) by amount.
signal target_hit(target: Node, amount: float)
signal shield_broken
## An ability request was refused. ability: &"magic_bolt", &"dash", &"package_shield".
## reason: &"cooldown", &"dashing", &"dead", &"no_body", &"no_package", &"shield_depleted".
signal ability_blocked(ability: StringName, reason: StringName)

## Group the owning body joins so enemies can find the courier.
const PLAYER_GROUP := &"combat_player"
## Physics layer bits used by Phase 4 combat (layers 1, 2 and 5).
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 16

const MAGIC_BOLT_SCENE := preload("res://scenes/gameplay/combat/magic_bolt.tscn")

@export var health: CombatHealth
## Handle the combat input actions. A PlayerController parent's input_enabled also applies.
@export var input_enabled: bool = true
## Advance timers and dash movement every physics frame.
@export var simulate: bool = true
@export var register_as_player_target: bool = true

@export_group("Magic Bolt")
## Scene whose root is a CombatProjectile. Defaults to the Phase 4 magic bolt.
@export var magic_bolt_scene: PackedScene
@export var bolt_damage: float = 20.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var bolt_cooldown: float = 0.45
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var bolt_speed: float = 18.0
@export_range(0.1, 100.0, 0.1, "suffix:m") var bolt_range: float = 18.0
@export var bolt_spawn_height: float = 0.8
@export var bolt_spawn_forward: float = 0.3
@export_flags_3d_physics var bolt_collision_mask: int = WORLD_LAYER | ENEMY_LAYER

@export_group("Dash")
@export_range(0.1, 60.0, 0.1, "suffix:m/s") var dash_speed: float = 16.0
@export_range(0.01, 2.0, 0.01, "suffix:s") var dash_duration: float = 0.2
## Counted from the start of the dash.
@export_range(0.0, 10.0, 0.05, "suffix:s") var dash_cooldown: float = 0.9
@export var dash_invulnerable: bool = true

@export_group("Package Shield")
@export var shield_max_durability: float = 60.0
## Durability required to raise the shield (after breaking it or lowering it).
@export var shield_min_activation: float = 15.0
@export var shield_regen_per_second: float = 8.0
## Seconds after the last absorbed hit / lowering before durability regenerates.
@export var shield_regen_delay: float = 2.0

@export_group("Package Damage")
## Unabsorbed damage taken while carrying applies damage * this as package impact force.
@export var package_impact_per_damage: float = 0.25

var _body: CharacterBody3D = null
var _carrier: PackageCarrier = null
var _bolt_cooldown_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_time_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _shield_active: bool = false
var _shield_durability: float = -1.0
var _shield_regen_wait: float = 0.0


func _ready() -> void:
	if _shield_durability < 0.0:
		_shield_durability = shield_max_durability
	_body = get_parent() as CharacterBody3D
	if health == null:
		health = CombatHealth.find_on(self)
	if health != null:
		health.damage_interceptor = _intercept_damage
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	if _body != null:
		if register_as_player_target:
			_body.add_to_group(PLAYER_GROUP)
		_carrier = PackageCarrier.find_on(_body)
	if _carrier != null:
		_carrier.carried_package_changed.connect(_on_carried_package_changed)


func _physics_process(delta: float) -> void:
	if simulate:
		advance(delta)


## Finds the controller on a body (e.g. Player/Combat). Returns null when there is none.
static func find_on(node: Node) -> CombatController:
	if node == null:
		return null
	if node is CombatController:
		return node
	for child in node.get_children():
		if child is CombatController:
			return child
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not _accepts_input():
		return
	if event.is_action_pressed(&"combat_magic_bolt"):
		try_magic_bolt()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"combat_dash"):
		try_dash()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"package_shield"):
		toggle_package_shield()
		get_viewport().set_input_as_handled()


## Steps cooldowns, the active dash, and shield regeneration by delta seconds.
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_bolt_cooldown_left = maxf(_bolt_cooldown_left - delta, 0.0)
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	if _dash_time_left > 0.0:
		_step_dash(delta)
	_step_shield_regen(delta)


# --- Magic Bolt ------------------------------------------------------------------

## Fires a bolt along direction (or the aim direction when zero). Returns the result.
func try_magic_bolt(direction := Vector3.ZERO) -> bool:
	if _is_dead():
		return _block(&"magic_bolt", &"dead")
	if _bolt_cooldown_left > 0.0:
		return _block(&"magic_bolt", &"cooldown")
	if _body == null or not _body.is_inside_tree() or _body.get_parent() == null:
		return _block(&"magic_bolt", &"no_body")
	var aim := _flatten(direction)
	if aim == Vector3.ZERO:
		aim = get_aim_direction()
	var origin := _body.global_position + Vector3.UP * bolt_spawn_height + aim * bolt_spawn_forward
	var scene := magic_bolt_scene if magic_bolt_scene != null else MAGIC_BOLT_SCENE
	var bolt := scene.instantiate() as CombatProjectile
	bolt.damage = bolt_damage
	bolt.speed = bolt_speed
	bolt.max_distance = bolt_range
	bolt.collision_mask = bolt_collision_mask
	bolt.direction = aim
	bolt.source = _body
	_body.get_parent().add_child(bolt)
	bolt.global_position = origin
	bolt.reset_physics_interpolation()
	bolt.hit.connect(_on_bolt_hit)
	_bolt_cooldown_left = bolt_cooldown
	magic_bolt_fired.emit(origin, aim)
	return true


func get_magic_bolt_cooldown_remaining() -> float:
	return _bolt_cooldown_left


func is_magic_bolt_ready() -> bool:
	return _bolt_cooldown_left <= 0.0 and not _is_dead()


## Flat (XZ) unit vector: current movement input, else the visual facing, else -Z of the body.
func get_aim_direction() -> Vector3:
	var player := _body as PlayerController
	if player != null:
		var moving := _flatten(player.move_direction)
		if moving != Vector3.ZERO:
			return moving
		if player.facing != null:
			var facing := _flatten(player.facing.get_facing_direction())
			if facing != Vector3.ZERO:
				return facing
	if _body != null:
		var forward := _flatten(-_body.global_basis.z)
		if forward != Vector3.ZERO:
			return forward
	return Vector3.FORWARD


# --- Dash ------------------------------------------------------------------------

## Starts a dash along direction (or the aim direction when zero). Returns the result.
func try_dash(direction := Vector3.ZERO) -> bool:
	if _is_dead():
		return _block(&"dash", &"dead")
	if is_dashing():
		return _block(&"dash", &"dashing")
	if _dash_cooldown_left > 0.0:
		return _block(&"dash", &"cooldown")
	if _body == null:
		return _block(&"dash", &"no_body")
	var dash_direction := _flatten(direction)
	if dash_direction == Vector3.ZERO:
		dash_direction = get_aim_direction()
	_dash_direction = dash_direction
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	dash_started.emit()
	return true


func is_dashing() -> bool:
	return _dash_time_left > 0.0


func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_left


func get_dash_direction() -> Vector3:
	return _dash_direction


func _step_dash(delta: float) -> void:
	var step := minf(delta, _dash_time_left)
	if _body != null and _body.is_inside_tree():
		var collision := _body.move_and_collide(_dash_direction * dash_speed * step)
		if collision != null:
			_body.move_and_collide(collision.get_remainder().slide(collision.get_normal()))
	_dash_time_left -= step
	if _dash_time_left <= 0.0:
		_end_dash()


func _end_dash() -> void:
	_dash_time_left = 0.0
	dash_finished.emit()


# --- Package Shield --------------------------------------------------------------

## Raises (true) or lowers (false) the shield. Raising requires a carried package and at
## least shield_min_activation durability. Lowering always succeeds. Returns whether the
## shield is now in the requested state.
func set_package_shield_enabled(enabled: bool) -> bool:
	if not enabled:
		if _shield_active:
			_shield_active = false
			_shield_regen_wait = shield_regen_delay
			shield_changed.emit(false, _shield_durability)
		return true
	if _shield_active:
		return true
	if _is_dead():
		return _block(&"package_shield", &"dead")
	if not is_carrying_package():
		return _block(&"package_shield", &"no_package")
	if _shield_durability < shield_min_activation:
		return _block(&"package_shield", &"shield_depleted")
	_shield_active = true
	shield_changed.emit(true, _shield_durability)
	return true


func toggle_package_shield() -> bool:
	return set_package_shield_enabled(not _shield_active)


func is_shield_active() -> bool:
	return _shield_active


func get_shield_durability() -> float:
	return _shield_durability


func is_carrying_package() -> bool:
	return _carrier != null and _carrier.is_carrying()


func get_carrier() -> PackageCarrier:
	return _carrier


func _step_shield_regen(delta: float) -> void:
	if _shield_active or _shield_durability >= shield_max_durability:
		return
	if _shield_regen_wait > 0.0:
		_shield_regen_wait = maxf(_shield_regen_wait - delta, 0.0)
		return
	_shield_durability = minf(_shield_durability + shield_regen_per_second * delta, shield_max_durability)
	shield_changed.emit(false, _shield_durability)


func _break_shield() -> void:
	_shield_active = false
	_shield_durability = 0.0
	_shield_regen_wait = shield_regen_delay
	shield_changed.emit(false, 0.0)
	shield_broken.emit()


# --- Damage ----------------------------------------------------------------------

## CombatHealth.damage_interceptor: returns the damage that reaches health.
func _intercept_damage(amount: float, _source_position: Vector3) -> float:
	if dash_invulnerable and is_dashing():
		return 0.0
	if _shield_active:
		if not is_carrying_package():
			set_package_shield_enabled(false)
			return amount
		var absorbed := minf(amount, _shield_durability)
		_shield_regen_wait = shield_regen_delay
		if _shield_durability - absorbed <= 0.0:
			_break_shield()
		else:
			_shield_durability -= absorbed
			shield_changed.emit(true, _shield_durability)
		return amount - absorbed
	return amount


func _on_damaged(amount: float, _source_position: Vector3) -> void:
	if package_impact_per_damage > 0.0 and is_carrying_package():
		_carrier.get_package().apply_impact(amount * package_impact_per_damage)


func _on_died() -> void:
	if is_dashing():
		_end_dash()
	set_package_shield_enabled(false)


func _on_carried_package_changed(package: PackageInstance) -> void:
	if package == null and _shield_active:
		set_package_shield_enabled(false)


func _on_bolt_hit(target: Node, amount: float) -> void:
	target_hit.emit(target, amount)


# --- helpers ---------------------------------------------------------------------

func _is_dead() -> bool:
	return health != null and health.is_dead()


func _accepts_input() -> bool:
	if not input_enabled:
		return false
	var player := _body as PlayerController
	return player == null or player.input_enabled


func _block(ability: StringName, reason: StringName) -> bool:
	ability_blocked.emit(ability, reason)
	return false


static func _flatten(vector: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()
