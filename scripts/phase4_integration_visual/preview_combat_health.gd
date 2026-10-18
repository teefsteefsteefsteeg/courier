extends Node
## Preview-only stand-in for a gameplay CombatHealth (player or enemy). Same
## signal names and getters as the integration contract. Never instanced by
## gameplay scenes.

signal health_changed(current, maximum)
signal damaged(amount, source_position)
signal died

@export var max_health := 30.0

var current_health := 30.0


func _ready() -> void:
	current_health = max_health


func get_health() -> float:
	return current_health


func get_max_health() -> float:
	return max_health


func is_dead() -> bool:
	return current_health <= 0.0


## amount 0 reports a blocked hit (still emits damaged).
func apply_damage(amount: float, source_position := Vector3.INF) -> void:
	if is_dead():
		return
	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount, source_position)
	health_changed.emit(current_health, max_health)
	if is_dead():
		died.emit()


func revive() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
