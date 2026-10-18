class_name PackageVisualFX
extends Node3D
## Shared behaviour for low-poly package visuals: optional binding to a
## PackageInstance through PackageStatusProbe, an impact jolt whenever integrity
## drops, and a warning shake while the package is critical. Unbound visuals
## stay in their calm idle state, so spawners that never call bind_package()
## keep working unchanged. Setting metadata "package_instance" on the visual
## before it enters the tree binds it automatically.

signal warning_level_changed(level: int)

const META_PACKAGE := &"package_instance"

@export var critical_shake := 0.012
@export var impact_shake := 0.05
@export var impact_decay := 5.0

var probe := PackageStatusProbe.new()
var warning_level: int = PackageStatusProbe.WarningLevel.NONE

var _time := 0.0
var _impact := 0.0
var _last_integrity := -1.0
var _shake_targets: Array = []


func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			_shake_targets.append([child, (child as Node3D).position])
	probe.status_changed.connect(_on_status_changed)
	if has_meta(META_PACKAGE):
		var package: Variant = get_meta(META_PACKAGE)
		if package is Object:
			bind_package(package)
	update_visual(0.0)


func _process(delta: float) -> void:
	if probe.needs_polling():
		probe.poll()
	update_visual(delta)


func bind_package(package: Object) -> void:
	_last_integrity = -1.0
	probe.bind(package)
	update_visual(0.0)


func unbind_package() -> void:
	probe.unbind()
	_last_integrity = -1.0
	update_visual(0.0)


func get_bound_package() -> Object:
	return probe.target if probe.is_bound() else null


func get_impact() -> float:
	return _impact


func play_impact(strength := 1.0) -> void:
	_impact = maxf(_impact, clampf(strength, 0.0, 1.0))


## Advances animation by delta. Called every frame; public so tests and
## previews can drive it deterministically.
func update_visual(delta: float) -> void:
	_time += delta
	_impact = move_toward(_impact, 0.0, impact_decay * delta)
	var level: int = probe.get_warning_level() if probe.is_bound() else PackageStatusProbe.WarningLevel.NONE
	if level != warning_level:
		warning_level = level
		warning_level_changed.emit(level)
	_apply_shake()
	_update_effects(delta)


## Subclass hook for package-specific effects.
func _update_effects(_delta: float) -> void:
	pass


func _apply_shake() -> void:
	var amount := impact_shake * _impact
	if warning_level == PackageStatusProbe.WarningLevel.CRITICAL:
		amount += critical_shake
	for i in _shake_targets.size():
		var node: Node3D = _shake_targets[i][0]
		if not is_instance_valid(node):
			continue
		var offset := Vector3.ZERO
		if amount > 0.0:
			offset = Vector3(sin(_time * 53.0 + i * 2.1), 0.0, cos(_time * 47.0 + i * 1.7)) * amount
		node.position = _shake_targets[i][1] + offset


func _on_status_changed() -> void:
	if not probe.has_integrity():
		return
	var ratio := probe.get_integrity_ratio()
	if _last_integrity >= 0.0 and ratio < _last_integrity - 0.0001:
		play_impact(clampf((_last_integrity - ratio) * 5.0, 0.35, 1.0))
	_last_integrity = ratio


static func _set_emitting(particles: CPUParticles3D, emitting: bool) -> void:
	if particles != null and particles.emitting != emitting:
		particles.emitting = emitting
