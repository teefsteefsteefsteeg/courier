class_name CombatHealth
extends Node
## Hit points for anything that can be hurt in combat (the courier, enemies, props).
##
## Damage is applied synchronously through apply_damage(), so the same sequence of
## calls always produces the same state. An optional damage_interceptor (installed by
## CombatController for dash invulnerability and the Package Shield) may reduce the
## incoming amount before it reaches health.

## Emitted whenever current health changes (damage, heal, reset). Args: (current, max).
signal health_changed(current: float, maximum: float)
## Emitted after health was actually reduced. amount is the damage that got through.
signal damaged(amount: float, source_position: Vector3)
## Emitted once when health reaches 0. reset() re-arms it.
signal died
## Damage was fully negated (invulnerable, dash, shield). amount is the incoming value.
signal damage_blocked(amount: float, source_position: Vector3)
signal healed(amount: float)

@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
## While true, apply_damage() always returns false and emits damage_blocked.
@export var invulnerable: bool = false

## Optional Callable(amount: float, source_position: Vector3) -> float returning how much
## of the damage should still reach health. The result is clamped to 0..amount.
var damage_interceptor: Callable = Callable()
## Damage that got through on the most recent successful apply_damage() call.
var last_damage_taken: float = 0.0

var _current: float = -1.0
var _dead: bool = false


func _ready() -> void:
	_ensure_initialized()


## Finds the CombatHealth on a node, its children, or its grandchildren
## (e.g. Player/Combat/Health). Returns null when there is none.
static func find_on(node: Node) -> CombatHealth:
	if node == null:
		return null
	if node is CombatHealth:
		return node
	for child in node.get_children():
		if child is CombatHealth:
			return child
	for child in node.get_children():
		for grandchild in child.get_children():
			if grandchild is CombatHealth:
				return grandchild
	return null


func get_health() -> float:
	_ensure_initialized()
	return _current


func get_max_health() -> float:
	return max_health


## 0..1, for UI bars.
func get_health_ratio() -> float:
	return get_health() / max_health


func is_dead() -> bool:
	return _dead


## Reduces health by amount (after the interceptor). Returns true only if health was
## actually reduced; false when amount <= 0, already dead, invulnerable, or fully absorbed.
func apply_damage(amount: float, source_position := Vector3.ZERO) -> bool:
	_ensure_initialized()
	if amount <= 0.0 or _dead:
		return false
	if invulnerable:
		damage_blocked.emit(amount, source_position)
		return false
	var final_amount := amount
	if damage_interceptor.is_valid():
		final_amount = clampf(float(damage_interceptor.call(amount, source_position)), 0.0, amount)
	if final_amount <= 0.0:
		damage_blocked.emit(amount, source_position)
		return false
	_current = maxf(_current - final_amount, 0.0)
	last_damage_taken = final_amount
	damaged.emit(final_amount, source_position)
	health_changed.emit(_current, max_health)
	if _current <= 0.0:
		_dead = true
		died.emit()
	return true


## Restores up to amount health. Dead bodies cannot be healed (use reset()).
func heal(amount: float) -> float:
	_ensure_initialized()
	if amount <= 0.0 or _dead:
		return 0.0
	var old := _current
	_current = minf(_current + amount, max_health)
	var gained := _current - old
	if gained > 0.0:
		healed.emit(gained)
		health_changed.emit(_current, max_health)
	return gained


## Full health and alive again (respawn).
func reset() -> void:
	_dead = false
	_current = max_health
	last_damage_taken = 0.0
	health_changed.emit(_current, max_health)


func _ensure_initialized() -> void:
	if _current < 0.0:
		_current = max_health
