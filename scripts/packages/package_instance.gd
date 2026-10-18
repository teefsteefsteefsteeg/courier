class_name PackageInstance
extends RefCounted
## One physical package in play. Runtime values (integrity, temperature, instability)
## live here, never on the shared PackageDefinition resource.
##
## Phase 3 mechanics are deterministic: the same sequence of tick() / apply_impact()
## calls always produces the same state. PackageCarrier ticks the carried package each
## physics frame; PackagePickup ticks a dropped one (speed 0).
##
## Quality helpers (get_condition, get_reward_multiplier, get_adjusted_reward) let quest
## code scale payouts by package condition without this class knowing about quests.

enum Condition { PRISTINE, GOOD, DAMAGED, RUINED, DESTROYED }
enum TemperatureState { NOT_APPLICABLE, SAFE, TOO_COLD, TOO_HOT }

signal integrity_changed(new_value: float, old_value: float)
signal temperature_changed(new_value: float, old_value: float)
signal instability_changed(new_value: float, old_value: float)
signal condition_changed(new_condition: Condition, old_condition: Condition)
## Emitted once, when integrity reaches 0 (REASON_RUINED) or the package explodes (REASON_EXPLODED).
signal destroyed(reason: StringName)

const DEFAULT_AMBIENT_TEMPERATURE := 20.0
const MAX_INSTABILITY := 100.0
const REASON_RUINED := &"ruined"
const REASON_EXPLODED := &"exploded"
## Minimum integrity ratio (integrity / definition.integrity) for each condition.
const PRISTINE_MIN_RATIO := 0.9
const GOOD_MIN_RATIO := 0.6
const DAMAGED_MIN_RATIO := 0.25
## Reward multiplier per Condition, indexed by enum value.
const REWARD_MULTIPLIERS := [1.0, 0.8, 0.5, 0.2, 0.0]

var definition: PackageDefinition
var integrity: float
var temperature: float
var instability: float

var _destroyed: bool = false
var _destroyed_reason: StringName = &""
var _condition: Condition = Condition.PRISTINE


func _init(package_definition: PackageDefinition) -> void:
	definition = package_definition
	integrity = package_definition.integrity
	temperature = package_definition.starting_temperature
	instability = clampf(package_definition.starting_instability, 0.0, MAX_INSTABILITY)
	_condition = _compute_condition()


func get_package_id() -> StringName:
	return definition.package_id


func get_quest_id() -> StringName:
	return definition.quest_id


func get_recipient_id() -> StringName:
	return definition.recipient_id


func set_integrity(value: float) -> void:
	var old := integrity
	integrity = clampf(value, 0.0, definition.integrity)
	if not is_equal_approx(old, integrity):
		integrity_changed.emit(integrity, old)
	if integrity <= 0.0 and not _destroyed:
		_destroy(REASON_RUINED)
	else:
		_refresh_condition()


# --- simulation -----------------------------------------------------------------

## Advances the package's mechanic by delta seconds. movement_speed is the carrier's
## speed in m/s (0 when lying on the ground). No-op once destroyed.
func tick(delta: float, movement_speed: float = 0.0, ambient_temperature: float = DEFAULT_AMBIENT_TEMPERATURE) -> void:
	if delta <= 0.0 or _destroyed:
		return
	match definition.behavior:
		PackageDefinition.Behavior.TEMPERATURE:
			_tick_temperature(delta, ambient_temperature)
		PackageDefinition.Behavior.INSTABILITY:
			_tick_instability(delta, movement_speed)


## A bump or drop. Costs force * impact_sensitivity integrity; unstable packages also
## gain force * instability_per_impact instability (applied first, so it may explode).
func apply_impact(force: float) -> void:
	if force <= 0.0 or _destroyed:
		return
	if uses_instability():
		add_instability(force * definition.instability_per_impact)
	if not _destroyed:
		set_integrity(integrity - force * definition.impact_sensitivity)


func is_destroyed() -> bool:
	return _destroyed


## &"" while intact, otherwise REASON_RUINED or REASON_EXPLODED.
func get_destroyed_reason() -> StringName:
	return _destroyed_reason


## Player-facing failure text, e.g. for QuestManager.fail_quest().
func get_destroyed_message() -> String:
	if _destroyed_reason == REASON_EXPLODED:
		return "The %s exploded!" % definition.package_name
	return "The %s was ruined." % definition.package_name


# --- temperature ----------------------------------------------------------------

func uses_temperature() -> bool:
	return definition.behavior == PackageDefinition.Behavior.TEMPERATURE


func get_temperature() -> float:
	return temperature


func set_temperature(value: float) -> void:
	var old := temperature
	temperature = value
	if not is_equal_approx(old, temperature):
		temperature_changed.emit(temperature, old)


func get_temperature_state() -> TemperatureState:
	if not uses_temperature():
		return TemperatureState.NOT_APPLICABLE
	if temperature < definition.ideal_temperature_min:
		return TemperatureState.TOO_COLD
	if temperature > definition.ideal_temperature_max:
		return TemperatureState.TOO_HOT
	return TemperatureState.SAFE


## True for packages without a temperature mechanic.
func is_temperature_safe() -> bool:
	var state := get_temperature_state()
	return state != TemperatureState.TOO_COLD and state != TemperatureState.TOO_HOT


# --- instability ----------------------------------------------------------------

func uses_instability() -> bool:
	return definition.behavior == PackageDefinition.Behavior.INSTABILITY


func get_instability() -> float:
	return instability


## Clamped to 0..MAX_INSTABILITY. Reaching the max explodes INSTABILITY packages.
func set_instability(value: float) -> void:
	if _destroyed:
		return
	var old := instability
	instability = clampf(value, 0.0, MAX_INSTABILITY)
	if not is_equal_approx(old, instability):
		instability_changed.emit(instability, old)
	if uses_instability() and instability >= MAX_INSTABILITY:
		_destroy(REASON_EXPLODED)


func add_instability(amount: float) -> void:
	set_instability(instability + amount)


## 0..1, for UI meters.
func get_instability_ratio() -> float:
	return instability / MAX_INSTABILITY


# --- condition & rewards --------------------------------------------------------

## integrity / maximum integrity, 0..1.
func get_integrity_ratio() -> float:
	return integrity / definition.integrity if definition.integrity > 0.0 else 0.0


## 0..1 delivery quality: the integrity ratio, or 0 once destroyed.
func get_quality() -> float:
	return 0.0 if _destroyed else get_integrity_ratio()


func get_condition() -> Condition:
	return _condition


func get_condition_name() -> String:
	return condition_name(_condition)


func get_reward_multiplier() -> float:
	return reward_multiplier_for(_condition)


## Scales an amount by the current reward multiplier (rounded to nearest int).
func apply_reward_multiplier(amount: int) -> int:
	return roundi(amount * get_reward_multiplier())


## Returns a new QuestReward scaled by condition; the original is not modified.
## Negative reputation (penalties) is never reduced.
func get_adjusted_reward(reward: QuestReward) -> QuestReward:
	if reward == null:
		return null
	var adjusted := QuestReward.new()
	adjusted.gold = apply_reward_multiplier(reward.gold)
	adjusted.reputation = reward.reputation if reward.reputation < 0 else apply_reward_multiplier(reward.reputation)
	return adjusted


static func condition_for_ratio(ratio: float) -> Condition:
	if ratio >= PRISTINE_MIN_RATIO:
		return Condition.PRISTINE
	if ratio >= GOOD_MIN_RATIO:
		return Condition.GOOD
	if ratio >= DAMAGED_MIN_RATIO:
		return Condition.DAMAGED
	return Condition.RUINED


static func reward_multiplier_for(condition: Condition) -> float:
	return float(REWARD_MULTIPLIERS[condition])


static func condition_name(condition: Condition) -> String:
	match condition:
		Condition.PRISTINE: return "Pristine"
		Condition.GOOD: return "Good"
		Condition.DAMAGED: return "Damaged"
		Condition.RUINED: return "Ruined"
		Condition.DESTROYED: return "Destroyed"
	return "?"


# --- internals ------------------------------------------------------------------

func _tick_temperature(delta: float, ambient_temperature: float) -> void:
	set_temperature(move_toward(temperature, ambient_temperature, definition.temperature_change_rate * delta))
	if not is_temperature_safe():
		set_integrity(integrity - definition.temperature_damage_per_second * delta)


func _tick_instability(delta: float, movement_speed: float) -> void:
	var excess := movement_speed - definition.instability_safe_speed
	if excess > 0.0:
		add_instability(excess * definition.instability_gain_per_speed * delta)
	else:
		add_instability(-definition.instability_recovery_per_second * delta)
	if not _destroyed and instability >= definition.instability_damage_threshold:
		set_integrity(integrity - definition.instability_damage_per_second * delta)


func _destroy(reason: StringName) -> void:
	_destroyed = true
	_destroyed_reason = reason
	if integrity > 0.0:
		set_integrity(0.0)
	_refresh_condition()
	destroyed.emit(reason)


func _compute_condition() -> Condition:
	return Condition.DESTROYED if _destroyed else condition_for_ratio(get_integrity_ratio())


func _refresh_condition() -> void:
	var old := _condition
	_condition = _compute_condition()
	if _condition != old:
		condition_changed.emit(_condition, old)
