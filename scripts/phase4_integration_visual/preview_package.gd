extends Node
## Preview-only package stand-in exposing the Phase 3 status names that
## PackageStatusProbe detects (temperature, instability, integrity) plus a
## damaged signal. Never instanced by gameplay scenes.

signal temperature_changed(value)
signal instability_changed(value)
signal integrity_changed(value)
signal damaged(amount)

var display_name := "Moonpetal Tonic"
var temperature := 50.0
var instability := 0.0
var max_instability := 1.0
var integrity := 100.0
var max_integrity := 100.0


func get_max_integrity() -> float:
	return max_integrity


func set_temperature(value: float) -> void:
	temperature = clampf(value, 0.0, 100.0)
	temperature_changed.emit(temperature)


func set_instability(value: float) -> void:
	instability = clampf(value, 0.0, max_instability)
	instability_changed.emit(instability)


func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	integrity = maxf(0.0, integrity - amount)
	damaged.emit(amount)
	integrity_changed.emit(integrity)


func reset() -> void:
	set_temperature(50.0)
	set_instability(0.0)
	integrity = max_integrity
	integrity_changed.emit(integrity)
