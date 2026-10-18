class_name PackageStatusProbe
extends RefCounted
## Read-only adapter over a PackageInstance (or any Object) that feature-detects
## the optional Phase 3 status API. Nothing here requires those members to
## exist: missing features report has_*() == false and neutral defaults, so a
## plain Phase 2 PackageInstance binds cleanly and simply shows nothing.
##
## Detected per feature, first match wins (target first, then target.definition
## for limits/ranges):
##   temperature  uses_temperature() -> bool (optional gate)
##                get_temperature() -> float | var temperature
##                get_temperature_limits() -> Vector2 | var temperature_limits
##                  | get_min_temperature()/get_max_temperature()
##                  | var min_temperature/max_temperature     (default 0..100)
##                get_safe_temperature_range() -> Vector2 | var safe_temperature_range
##                  | var safe_temperature_min/safe_temperature_max
##                  (default: middle 35%..65% of the limits)
##                signal temperature_changed(...)  (else values are polled)
##   instability  uses_instability() -> bool (optional gate)
##                get_instability() -> float | var instability
##                get_instability_ratio() -> float (optional, 0..1, overrides)
##                get_max_instability() -> float | var max_instability (default 1.0)
##                signal instability_changed(...)  (else values are polled)
##   integrity    get_integrity() | var integrity; max from get_max_integrity()
##                or definition.integrity; signal integrity_changed(...)
## Change signals may carry any number of arguments; they are ignored.

signal status_changed

enum WarningLevel { NONE, CAUTION, CRITICAL }

const DEFAULT_TEMPERATURE_LIMITS := Vector2(0.0, 100.0)
const DEFAULT_SAFE_BAND := Vector2(0.35, 0.65)
const DEFAULT_MAX_INSTABILITY := 1.0
const CAUTION_INSTABILITY := 0.5
const CRITICAL_INSTABILITY := 0.8
const CRITICAL_TEMPERATURE_DANGER := 0.6

const _CHANGE_SIGNALS: Array[StringName] = [
	&"temperature_changed",
	&"instability_changed",
	&"integrity_changed",
	&"status_changed",
]

var target: Object

var _connections: Array = []
var _snapshot_cache := Vector3.ZERO


func _init(target_object: Object = null) -> void:
	if target_object != null:
		bind(target_object)


func bind(target_object: Object) -> void:
	unbind()
	target = target_object
	if target == null:
		return
	for signal_name in _CHANGE_SIGNALS:
		_connect_change(signal_name)
	_snapshot_cache = _snapshot()
	status_changed.emit()


func unbind() -> void:
	if is_bound():
		for connection: Array in _connections:
			if target.is_connected(connection[0], connection[1]):
				target.disconnect(connection[0], connection[1])
	_connections.clear()
	target = null


func is_bound() -> bool:
	return target != null and is_instance_valid(target)


## True when a tracked value has no change signal, so callers should poll().
func needs_polling() -> bool:
	if not is_bound():
		return false
	if has_temperature() and not target.has_signal(&"temperature_changed"):
		return true
	if has_instability() and not target.has_signal(&"instability_changed"):
		return true
	return false


## Re-reads values; emits status_changed and returns true if any changed.
func poll() -> bool:
	if not is_bound():
		return false
	var snapshot := _snapshot()
	if snapshot.is_equal_approx(_snapshot_cache):
		return false
	_snapshot_cache = snapshot
	status_changed.emit()
	return true


# --- temperature -------------------------------------------------------------

func has_temperature() -> bool:
	return _has_feature(&"uses_temperature", &"get_temperature", &"temperature")


func get_temperature() -> float:
	return float(_lookup(&"get_temperature", &"temperature", 0.0))


func get_temperature_limits() -> Vector2:
	var value: Variant = _lookup(&"get_temperature_limits", &"temperature_limits", null, true)
	if value != null:
		return _to_range(value, DEFAULT_TEMPERATURE_LIMITS)
	var low: Variant = _lookup(&"get_min_temperature", &"min_temperature", null, true)
	var high: Variant = _lookup(&"get_max_temperature", &"max_temperature", null, true)
	if low != null and high != null:
		return _to_range(Vector2(float(low), float(high)), DEFAULT_TEMPERATURE_LIMITS)
	return DEFAULT_TEMPERATURE_LIMITS


func get_safe_temperature_range() -> Vector2:
	var limits := get_temperature_limits()
	var fallback := Vector2(
		lerpf(limits.x, limits.y, DEFAULT_SAFE_BAND.x),
		lerpf(limits.x, limits.y, DEFAULT_SAFE_BAND.y))
	var safe := fallback
	var value: Variant = _lookup(&"get_safe_temperature_range", &"safe_temperature_range", null, true)
	if value != null:
		safe = _to_range(value, fallback)
	else:
		var low: Variant = _lookup(&"get_safe_temperature_min", &"safe_temperature_min", null, true)
		var high: Variant = _lookup(&"get_safe_temperature_max", &"safe_temperature_max", null, true)
		if low != null and high != null:
			safe = _to_range(Vector2(float(low), float(high)), fallback)
	return Vector2(clampf(safe.x, limits.x, limits.y), clampf(safe.y, limits.x, limits.y))


## 0 at the cold limit, 1 at the hot limit.
func get_temperature_ratio() -> float:
	if not has_temperature():
		return 0.5
	var limits := get_temperature_limits()
	return clampf(inverse_lerp(limits.x, limits.y, get_temperature()), 0.0, 1.0)


## 0 inside the safe range, rising to 1 at either limit.
func get_temperature_danger() -> float:
	return absf(get_temperature_bias())


## Signed danger: -1 freezing .. 0 safe .. +1 overheating.
func get_temperature_bias() -> float:
	if not has_temperature():
		return 0.0
	return temperature_bias(get_temperature(), get_temperature_limits(), get_safe_temperature_range())


static func temperature_bias(temperature: float, limits: Vector2, safe: Vector2) -> float:
	if temperature < safe.x:
		var span := safe.x - limits.x
		return -1.0 if span <= 0.0 else -clampf((safe.x - temperature) / span, 0.0, 1.0)
	if temperature > safe.y:
		var span := limits.y - safe.y
		return 1.0 if span <= 0.0 else clampf((temperature - safe.y) / span, 0.0, 1.0)
	return 0.0


# --- instability -------------------------------------------------------------

func has_instability() -> bool:
	return _has_feature(&"uses_instability", &"get_instability", &"instability")


func get_instability() -> float:
	return float(_lookup(&"get_instability", &"instability", 0.0))


func get_max_instability() -> float:
	var value := float(_lookup(&"get_max_instability", &"max_instability", DEFAULT_MAX_INSTABILITY, true))
	return value if value > 0.0 else DEFAULT_MAX_INSTABILITY


func get_instability_ratio() -> float:
	if not has_instability():
		return 0.0
	if target.has_method(&"get_instability_ratio"):
		return clampf(float(target.call(&"get_instability_ratio")), 0.0, 1.0)
	return clampf(get_instability() / get_max_instability(), 0.0, 1.0)


# --- integrity ---------------------------------------------------------------

func has_integrity() -> bool:
	return _has_feature(&"", &"get_integrity", &"integrity")


func get_integrity_ratio() -> float:
	if not has_integrity():
		return 1.0
	var maximum := 0.0
	if target.has_method(&"get_max_integrity"):
		maximum = float(target.call(&"get_max_integrity"))
	else:
		var definition := _definition()
		if definition != null and "integrity" in definition:
			maximum = float(definition.get(&"integrity"))
	if maximum <= 0.0:
		return 1.0
	return clampf(float(_lookup(&"get_integrity", &"integrity", maximum)) / maximum, 0.0, 1.0)


# --- summary -----------------------------------------------------------------

func get_warning_level() -> int:
	return warning_for(get_temperature_danger(), get_instability_ratio())


static func warning_for(temperature_danger: float, instability_ratio: float) -> int:
	if temperature_danger >= CRITICAL_TEMPERATURE_DANGER or instability_ratio >= CRITICAL_INSTABILITY:
		return WarningLevel.CRITICAL
	if temperature_danger > 0.0 or instability_ratio >= CAUTION_INSTABILITY:
		return WarningLevel.CAUTION
	return WarningLevel.NONE


func get_display_name() -> String:
	var value: Variant = _lookup(&"get_display_name", &"display_name", null, true)
	if value != null and str(value) != "":
		return str(value)
	if is_bound() and target.has_method(&"get_package_id"):
		return str(target.call(&"get_package_id")).capitalize()
	return "Package"


# --- internals ---------------------------------------------------------------

func _has_feature(flag_method: StringName, getter: StringName, property: StringName) -> bool:
	if not is_bound():
		return false
	if flag_method != &"" and target.has_method(flag_method):
		return bool(target.call(flag_method))
	return target.has_method(getter) or String(property) in target


func _lookup(method: StringName, property: StringName, fallback: Variant, search_definition := false) -> Variant:
	if not is_bound():
		return fallback
	if target.has_method(method):
		return target.call(method)
	if String(property) in target:
		return target.get(property)
	if search_definition:
		var definition := _definition()
		if definition != null:
			if definition.has_method(method):
				return definition.call(method)
			if String(property) in definition:
				return definition.get(property)
	return fallback


func _definition() -> Object:
	if not is_bound() or not ("definition" in target):
		return null
	var definition: Variant = target.get(&"definition")
	return definition as Object if definition is Object else null


func _snapshot() -> Vector3:
	return Vector3(
		get_temperature() if has_temperature() else 0.0,
		get_instability_ratio(),
		get_integrity_ratio())


func _connect_change(signal_name: StringName) -> void:
	if not target.has_signal(signal_name):
		return
	var arg_count := _signal_arg_count(signal_name)
	var callback: Callable = _on_target_changed.unbind(arg_count) if arg_count > 0 else _on_target_changed
	target.connect(signal_name, callback)
	_connections.append([signal_name, callback])


func _signal_arg_count(signal_name: StringName) -> int:
	for info: Dictionary in target.get_signal_list():
		if StringName(info["name"]) == signal_name:
			return (info["args"] as Array).size()
	return 0


func _on_target_changed() -> void:
	_snapshot_cache = _snapshot()
	status_changed.emit()


static func _to_range(value: Variant, fallback: Vector2) -> Vector2:
	var result := fallback
	if value is Vector2:
		result = value
	elif value is Vector2i:
		result = Vector2(value)
	elif value is Array and (value as Array).size() >= 2:
		result = Vector2(float(value[0]), float(value[1]))
	return result if result.y > result.x else fallback
