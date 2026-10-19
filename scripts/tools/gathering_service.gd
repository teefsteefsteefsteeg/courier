class_name GatheringService
extends Node
## World state of the Phase 5H tool interactions, in GameplayServices next to the wallet
## and inventory. ToolTargets (trees, rocks, dig spots, repairable structures) are keyed by
## their stable target_id:
## - depleted harvest nodes and when they grow back (real time, so a tree felled before
##   quitting is still a stump after a quick reload, and has regrown after a long break);
## - repaired structures, permanently. mark_repaired() succeeds once per id, so a repair
##   reward can never be paid twice;
## - lifetime counts per gathering activity (for the journal-style summary and tests).
## SaveGame stores to_dict() under "gathering"; saves without it start fresh.

signal changed
## A depleted node's time is up (emitted when queried or on the periodic check).
signal respawned(target_id: StringName)

const GROUP := &"gathering_service"
## Depleted with this respawn time never grows back.
const NEVER := -1.0
const CHECK_INTERVAL := 1.0

## Seconds since the epoch; tests swap in a fake clock.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()

## target_id -> unix time it grows back (NEVER = permanent).
var _depleted: Dictionary[StringName, float] = {}
var _repaired: Dictionary[StringName, bool] = {}
var _counts: Dictionary[StringName, int] = {}
var _check_left := CHECK_INTERVAL


func _enter_tree() -> void:
	add_to_group(GROUP)


static func find(tree: SceneTree) -> GatheringService:
	return tree.get_first_node_in_group(GROUP) as GatheringService


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	for id in _depleted.keys():
		is_depleted(id)


## True while target_id is used up. Clears (and emits respawned) once its time has come.
func is_depleted(target_id: StringName) -> bool:
	if not _depleted.has(target_id):
		return false
	var until: float = _depleted[target_id]
	if until != NEVER and clock.call() >= until:
		_depleted.erase(target_id)
		respawned.emit(target_id)
		changed.emit()
		return false
	return true


## Seconds until target_id grows back (0 when available, INF when never).
func seconds_until_respawn(target_id: StringName) -> float:
	if not is_depleted(target_id):
		return 0.0
	var until: float = _depleted[target_id]
	return INF if until == NEVER else maxf(until - clock.call(), 0.0)


## Marks target_id used up for respawn_seconds (<= 0: for good).
func mark_depleted(target_id: StringName, respawn_seconds: float) -> void:
	_depleted[target_id] = clock.call() + respawn_seconds if respawn_seconds > 0.0 else NEVER
	changed.emit()


func is_repaired(target_id: StringName) -> bool:
	return _repaired.has(target_id)


## Records a finished repair. False when it was already repaired (no second reward).
func mark_repaired(target_id: StringName) -> bool:
	if _repaired.has(target_id):
		return false
	_repaired[target_id] = true
	changed.emit()
	return true


## Lifetime tally of an activity (&"fish", &"chop", &"mine", &"dig", &"repair").
func add_count(activity: StringName, amount: int = 1) -> void:
	_counts[activity] = get_count(activity) + amount
	changed.emit()


func get_count(activity: StringName) -> int:
	return _counts.get(activity, 0)


func to_dict() -> Dictionary:
	var depleted := {}
	for id in _depleted:
		depleted[String(id)] = _depleted[id]
	var counts := {}
	for id in _counts:
		counts[String(id)] = _counts[id]
	return {
		"depleted": depleted,
		"repaired": _repaired.keys().map(func(id: StringName) -> String: return String(id)),
		"counts": counts,
	}


func from_dict(data: Dictionary) -> void:
	_depleted.clear()
	_repaired.clear()
	_counts.clear()
	var depleted: Dictionary = data.get("depleted", {})
	for id in depleted:
		_depleted[StringName(id)] = float(depleted[id])
	for id in data.get("repaired", []):
		_repaired[StringName(id)] = true
	var counts: Dictionary = data.get("counts", {})
	for id in counts:
		_counts[StringName(id)] = int(counts[id])
	changed.emit()
