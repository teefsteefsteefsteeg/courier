class_name CombatController
extends Node
## Courier combat abilities, added as the "Combat" child of a CharacterBody3D:
## - Primary attack (try_attack, the combat_magic_bolt action), chosen by the attack style
##   EquipmentStats sets from the equipped weapon's type:
##   MAGIC_BOLT (bare hands or a staff): ranged projectile along the aim direction.
##   FAST_MELEE (sword) / HEAVY_MELEE (axe): a swing that, after melee_windup seconds,
##   damages every enemy within melee_range and melee_arc_degrees in front.
##   ARROW (bow): a faster, longer-range projectile with the arrow model.
##   TOOL (a tool in the main hand, Phase 5H): no attack at all. The primary action emits
##   tool_use_requested instead (ToolUser works the tool on the object in front), so a tool
##   can never damage anyone and a weapon can never fish, chop, mine or repair.
##   All share one cooldown (the "bolt" cooldown the HUD shows), which switching weapons
##   never shortens. A switch cancels a swing that has not landed yet; switch_delay (off by
##   default) can add a minimum wait before the next attack.
## - Dash: short burst of movement; the body takes no damage while dashing. Each dash costs
##   dash_stamina_cost stamina (and starts dash_cooldown); stamina regenerates at
##   stamina_regen_per_second once stamina_regen_delay has passed since the last dash ended.
##   Below the cost the dash is refused ("no_stamina") while stamina keeps regenerating.
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
## A melee swing started (heavy: axe). Its hit lands melee_windup seconds later.
signal melee_started(direction: Vector3, heavy: bool)
## A swing landed; hits = enemies damaged (0 for a miss).
signal melee_resolved(hits: int)
## A swing was cut short before landing (weapon switched, knocked out).
signal melee_cancelled
signal arrow_fired(origin: Vector3, direction: Vector3)
signal dash_started
## The primary action was used with a tool in hand (AttackStyle.TOOL).
signal tool_use_requested
## Stamina changed (spent by a dash or regenerating).
signal stamina_changed(current: float, maximum: float)
signal dash_finished
## Emitted when the shield is raised/lowered/broken and whenever its durability changes.
signal shield_changed(active: bool, durability: float)
## A Magic Bolt damaged target (the body hit) by amount.
signal target_hit(target: Node, amount: float)
signal shield_broken
## An ability request was refused. ability: &"magic_bolt", &"melee", &"arrow", &"dash", &"package_shield".
## reason: &"cooldown", &"dashing", &"dead", &"no_body", &"no_package", &"shield_depleted",
## &"no_stamina".
signal ability_blocked(ability: StringName, reason: StringName)

## Group the owning body joins so enemies can find the courier.
const PLAYER_GROUP := &"combat_player"
## Physics layer bits used by Phase 4 combat (layers 1, 2 and 5).
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 16

const MAGIC_BOLT_SCENE := preload("res://scenes/gameplay/combat/magic_bolt.tscn")
const ARROW_SCENE := preload("res://scenes/gameplay/combat/arrow.tscn")

enum AttackStyle { MAGIC_BOLT, FAST_MELEE, HEAVY_MELEE, ARROW, TOOL }

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

@export_group("Melee")
@export var melee_damage: float = 20.0
@export_range(0.1, 10.0, 0.05, "suffix:m") var melee_range: float = 1.8
@export_range(0.0, 10.0, 0.01, "suffix:s") var melee_cooldown: float = 0.36
@export_range(10.0, 360.0, 5.0, "suffix:°") var melee_arc_degrees: float = 110.0
@export_range(0.0, 2.0, 0.01, "suffix:s") var melee_windup: float = 0.12

@export_group("Arrow")
@export var arrow_scene: PackedScene
@export var arrow_damage: float = 18.0
@export_range(0.1, 100.0, 0.1, "suffix:m/s") var arrow_speed: float = 28.0
@export_range(0.1, 100.0, 0.1, "suffix:m") var arrow_range: float = 26.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var arrow_cooldown: float = 0.7

@export_group("Weapon Switch")
## Minimum wait before the next attack after a weapon switch (0 = none). The shared
## cooldown is never shortened by a switch either way.
@export_range(0.0, 2.0, 0.01, "suffix:s") var switch_delay: float = 0.0

@export_group("Dash")
@export_range(0.1, 60.0, 0.1, "suffix:m/s") var dash_speed: float = 16.0
@export_range(0.01, 2.0, 0.01, "suffix:s") var dash_duration: float = 0.2
## Counted from the start of the dash.
@export_range(0.0, 10.0, 0.05, "suffix:s") var dash_cooldown: float = 0.9
@export var dash_invulnerable: bool = true

@export_group("Stamina")
@export var max_stamina: float = 100.0
## Stamina each dash costs; a dash needs at least this much.
@export var dash_stamina_cost: float = 25.0
@export_range(0.0, 500.0, 1.0, "suffix:/s") var stamina_regen_per_second: float = 60.0
## Seconds after the last dash ends before stamina starts regenerating.
@export_range(0.0, 5.0, 0.05, "suffix:s") var stamina_regen_delay: float = 0.7

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
var _stamina: float = -1.0
var _stamina_regen_wait: float = 0.0
var _attack_style: AttackStyle = AttackStyle.MAGIC_BOLT
var _melee_windup_left: float = -1.0
var _melee_direction: Vector3 = Vector3.ZERO
var _melee_heavy: bool = false
## Length of the primary cooldown last started (for the HUD's cooldown bar).
var _attack_cooldown_total: float = 0.45


func _ready() -> void:
	if _shield_durability < 0.0:
		_shield_durability = shield_max_durability
	if _stamina < 0.0:
		_stamina = max_stamina
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
		try_attack()
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
	if _melee_windup_left >= 0.0:
		_melee_windup_left -= delta
		if _melee_windup_left <= 0.0:
			_resolve_melee()
	if _dash_time_left > 0.0:
		_step_dash(delta)
	_step_stamina(delta)
	_step_shield_regen(delta)


# --- Primary attack ---------------------------------------------------------------

## Attacks with the current style along direction (or the aim direction when zero).
func try_attack(direction := Vector3.ZERO) -> bool:
	match _attack_style:
		AttackStyle.FAST_MELEE, AttackStyle.HEAVY_MELEE:
			return try_melee(direction)
		AttackStyle.ARROW:
			return try_arrow(direction)
		AttackStyle.TOOL:
			if health != null and health.is_dead():
				return _block(&"tool", &"dead")
			tool_use_requested.emit()
			return false
	return try_magic_bolt(direction)


func get_attack_style() -> AttackStyle:
	return _attack_style


## Sets the primary attack (EquipmentStats calls this from the equipped weapon). A
## different style counts as a weapon switch (see switch_weapon).
func set_attack_style(style: AttackStyle) -> void:
	if style == _attack_style:
		return
	_attack_style = style
	switch_weapon()


## The weapon in hand changed: a swing still winding up is cancelled (it never lands with
## the new weapon's stats). The running cooldown is kept; switch_delay can extend it.
func switch_weapon() -> void:
	cancel_melee()
	if switch_delay > _bolt_cooldown_left:
		_bolt_cooldown_left = switch_delay
		_attack_cooldown_total = switch_delay


## Seconds until the primary attack (any style) is ready. The combat HUD polls this.
func get_bolt_cooldown_remaining() -> float:
	return _bolt_cooldown_left


## Length of the primary cooldown now running, for the HUD's cooldown bar.
func get_bolt_cooldown() -> float:
	return _attack_cooldown_total


# --- Melee -----------------------------------------------------------------------

## Starts a swing (fast for a sword, heavy for an axe). The hit lands after melee_windup.
func try_melee(direction := Vector3.ZERO) -> bool:
	if _is_dead():
		return _block(&"melee", &"dead")
	if _bolt_cooldown_left > 0.0 or is_melee_pending():
		return _block(&"melee", &"cooldown")
	if _body == null or not _body.is_inside_tree():
		return _block(&"melee", &"no_body")
	var aim := _flatten(direction)
	_melee_direction = aim if aim != Vector3.ZERO else get_aim_direction()
	_melee_heavy = _attack_style == AttackStyle.HEAVY_MELEE
	_bolt_cooldown_left = melee_cooldown
	_attack_cooldown_total = melee_cooldown
	_melee_windup_left = melee_windup
	melee_started.emit(_melee_direction, _melee_heavy)
	if melee_windup <= 0.0:
		_resolve_melee()
	return true


func is_melee_pending() -> bool:
	return _melee_windup_left >= 0.0


func cancel_melee() -> void:
	if is_melee_pending():
		_melee_windup_left = -1.0
		melee_cancelled.emit()


## Enemies (CombatHealth on the enemy layer) inside a swing along direction, nearest first.
func get_melee_targets(direction: Vector3) -> Array[Node]:
	var targets: Array[Node] = []
	if _body == null or not _body.is_inside_tree():
		return targets
	var sphere := SphereShape3D.new()
	sphere.radius = melee_range
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, _body.global_position + Vector3.UP * bolt_spawn_height)
	query.collision_mask = ENEMY_LAYER
	query.collide_with_areas = false
	query.exclude = [_body.get_rid()]
	var half_arc := deg_to_rad(melee_arc_degrees) * 0.5
	var origin := _body.global_position
	for result: Dictionary in _body.get_world_3d().direct_space_state.intersect_shape(query, 32):
		var target := result.collider as Node3D
		if target == null or targets.has(target) or CombatHealth.find_on(target) == null:
			continue
		var to_target := _flatten(target.global_position - origin)
		if to_target == Vector3.ZERO or absf(direction.angle_to(to_target)) <= half_arc:
			targets.append(target)
	targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	return targets


func _resolve_melee() -> void:
	_melee_windup_left = -1.0
	var hits := 0
	if not _is_dead():
		for target in get_melee_targets(_melee_direction):
			var health := CombatHealth.find_on(target)
			if health.apply_damage(melee_damage, _body.global_position):
				hits += 1
				target_hit.emit(target, health.last_damage_taken)
	melee_resolved.emit(hits)


# --- Arrow -----------------------------------------------------------------------

## Fires an arrow along direction (or the aim direction when zero). Returns the result.
func try_arrow(direction := Vector3.ZERO) -> bool:
	if _is_dead():
		return _block(&"arrow", &"dead")
	if _bolt_cooldown_left > 0.0:
		return _block(&"arrow", &"cooldown")
	if _body == null or not _body.is_inside_tree() or _body.get_parent() == null:
		return _block(&"arrow", &"no_body")
	var aim := _flatten(direction)
	if aim == Vector3.ZERO:
		aim = get_aim_direction()
	var origin := _body.global_position + Vector3.UP * bolt_spawn_height + aim * bolt_spawn_forward
	var arrow := (arrow_scene if arrow_scene != null else ARROW_SCENE).instantiate() as CombatProjectile
	arrow.damage = arrow_damage
	arrow.speed = arrow_speed
	arrow.max_distance = arrow_range
	arrow.collision_mask = bolt_collision_mask
	arrow.direction = aim
	arrow.source = _body
	_body.get_parent().add_child(arrow)
	arrow.global_position = origin
	arrow.look_at(origin + aim, Vector3.UP)
	arrow.reset_physics_interpolation()
	arrow.hit.connect(_on_bolt_hit)
	_bolt_cooldown_left = arrow_cooldown
	_attack_cooldown_total = arrow_cooldown
	arrow_fired.emit(origin, aim)
	return true


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
	_attack_cooldown_total = bolt_cooldown
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
	if get_stamina() < dash_stamina_cost:
		return _block(&"dash", &"no_stamina")
	_stamina = get_stamina() - dash_stamina_cost
	_stamina_regen_wait = stamina_regen_delay
	stamina_changed.emit(_stamina, max_stamina)
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


## Stops a dash in progress now (teleport, cutscene). Its cooldown keeps running.
func cancel_dash() -> void:
	if is_dashing():
		_end_dash()


func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_left


func get_dash_direction() -> Vector3:
	return _dash_direction


func get_stamina() -> float:
	return _stamina if _stamina >= 0.0 else max_stamina


func get_max_stamina() -> float:
	return max_stamina


## True when stamina covers another dash.
func has_dash_stamina() -> bool:
	return get_stamina() >= dash_stamina_cost


## Regenerates stamina (delta-based) once the delay after the last dash has passed. The
## delay holds while a dash is still moving, and every new dash restarts it.
func _step_stamina(delta: float) -> void:
	if is_dashing():
		_stamina_regen_wait = stamina_regen_delay
		return
	if get_stamina() >= max_stamina:
		return
	if _stamina_regen_wait > 0.0:
		_stamina_regen_wait = maxf(_stamina_regen_wait - delta, 0.0)
		return
	_stamina = clampf(get_stamina() + stamina_regen_per_second * delta, 0.0, max_stamina)
	stamina_changed.emit(_stamina, max_stamina)


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
	cancel_melee()
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
