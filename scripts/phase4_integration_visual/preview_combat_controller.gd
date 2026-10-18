extends Node
## Preview-only stand-in for the gameplay CombatController. It emits the same
## signal names, so the standalone preview exercises the real by-name binding
## path. Never instanced by gameplay scenes.

signal magic_bolt_fired(origin, direction)
signal dash_started
signal dash_finished
signal shield_changed(active, durability)
signal target_hit(target, amount)

@export var bolt_cooldown := 0.6
@export var dash_cooldown := 0.9

var bolt_remaining := 0.0
var dash_remaining := 0.0


func _process(delta: float) -> void:
	bolt_remaining = maxf(0.0, bolt_remaining - delta)
	dash_remaining = maxf(0.0, dash_remaining - delta)


func get_bolt_cooldown_remaining() -> float:
	return bolt_remaining


func get_bolt_cooldown() -> float:
	return bolt_cooldown


func get_dash_cooldown_remaining() -> float:
	return dash_remaining


func get_dash_cooldown() -> float:
	return dash_cooldown


func fire(origin: Vector3, direction: Vector3) -> bool:
	if bolt_remaining > 0.0:
		return false
	bolt_remaining = bolt_cooldown
	magic_bolt_fired.emit(origin, direction)
	return true


func report_hit(target: Node, amount: float) -> void:
	target_hit.emit(target, amount)


func begin_dash() -> bool:
	if dash_remaining > 0.0:
		return false
	dash_started.emit()
	return true


func end_dash() -> void:
	dash_remaining = dash_cooldown
	dash_finished.emit()


func set_shield(active: bool, durability: float) -> void:
	shield_changed.emit(active, durability)


func reset() -> void:
	bolt_remaining = 0.0
	dash_remaining = 0.0
