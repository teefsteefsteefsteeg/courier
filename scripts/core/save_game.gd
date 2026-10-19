class_name SaveGame
extends Node
## Minimal save file (the project had none): wallet, inventory and equipment, finished
## quests, and one-time grants. JSON at `path`. Lives in GameplayServices.
##
## What is saved: gold, reputation, owned and equipped items, every quest that reached
## REWARDED (so a reward is never paid twice, even across sessions), and the
## starting-gold flag. Deliveries in progress are not saved (the carried package is not
## persisted); after a reload such a contract is simply on the board again.
##
## Loading and autosave run when `enabled`, which defaults to off in headless runs so
## automated tests never read or write the player's save. Run with `-- --new-game` to
## ignore and replace an existing save.
##
## Development/test mode (DevMode) grants DEV_STARTING_GOLD once per save.

signal loaded
signal saved

const GROUP := &"save_game"
const VERSION := 1
const DEV_STARTING_GOLD := 500

@export var path: String = "user://savegame.json"
## Load on start and save after changes. Off in headless runs unless forced.
@export var enabled: bool = true
@export var force_enabled_headless: bool = false
## Seconds to coalesce changes before writing.
@export_range(0.0, 10.0, 0.1, "suffix:s") var autosave_delay: float = 0.5

@export var wallet: CourierWallet
@export var inventory: CourierInventory
@export var quest_manager: QuestManager

var starting_gold_granted: bool = false
var _save_left: float = -1.0
var _restoring: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)


static func find(tree: SceneTree) -> SaveGame:
	return tree.get_first_node_in_group(GROUP) as SaveGame


func _ready() -> void:
	if wallet == null:
		wallet = CourierWallet.find(get_tree())
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if quest_manager == null:
		quest_manager = QuestManager.find(get_tree())
	if DisplayServer.get_name() == "headless" and not force_enabled_headless:
		enabled = false
	_start.call_deferred()


func _start() -> void:
	if enabled:
		if OS.get_cmdline_user_args().has("--new-game") and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		load_game()
	grant_dev_starting_gold()
	_watch()


func _process(delta: float) -> void:
	if _save_left < 0.0:
		return
	_save_left -= delta
	if _save_left < 0.0:
		save_game()


## Adds DEV_STARTING_GOLD once per save in development/test mode. Returns whether it paid.
func grant_dev_starting_gold(dev_mode: bool = DevMode.is_enabled()) -> bool:
	if not dev_mode or starting_gold_granted or wallet == null:
		return false
	starting_gold_granted = true
	wallet.add_gold(DEV_STARTING_GOLD)
	request_save()
	return true


func request_save() -> void:
	if enabled and not _restoring:
		_save_left = autosave_delay


func to_dict() -> Dictionary:
	var quests := {}
	if quest_manager != null:
		for quest_id in quest_manager.get_quest_ids():
			var state := quest_manager.get_state(quest_id)
			if state.status == QuestState.Status.REWARDED:
				quests[String(quest_id)] = state.to_dict()
	return {
		"version": VERSION,
		"wallet": {"gold": wallet.gold, "reputation": wallet.reputation} if wallet != null else {},
		"inventory": inventory.to_dict() if inventory != null else {},
		"quests": quests,
		"flags": {"starting_gold_granted": starting_gold_granted},
	}


func from_dict(data: Dictionary) -> void:
	_restoring = true
	var flags: Dictionary = data.get("flags", {})
	starting_gold_granted = bool(flags.get("starting_gold_granted", false))
	var saved_wallet: Dictionary = data.get("wallet", {})
	if wallet != null and not saved_wallet.is_empty():
		wallet.restore(int(saved_wallet.get("gold", 0)), int(saved_wallet.get("reputation", 0)))
	if inventory != null:
		inventory.from_dict(data.get("inventory", {}))
	if quest_manager != null:
		quest_manager.restore_finished_quests(data.get("quests", {}))
	_restoring = false
	loaded.emit()


func save_game() -> bool:
	_save_left = -1.0
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	saved.emit()
	return true


## Reads path if it exists. Returns whether a save was applied.
func load_game() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_warning("SaveGame: %s is not a valid save; ignoring it" % path)
		return false
	from_dict(json.data)
	return true


func _watch() -> void:
	if wallet != null:
		wallet.gold_changed.connect(func(_v, _d): request_save())
		wallet.reputation_changed.connect(func(_v, _d): request_save())
	if inventory != null:
		inventory.item_added.connect(func(_i): request_save())
		inventory.equipment_changed.connect(func(_s, _i): request_save())
		inventory.quick_slots_changed.connect(request_save)
	if quest_manager != null:
		quest_manager.quest_rewarded.connect(func(_q, _r): request_save())


func _exit_tree() -> void:
	# Flush a pending autosave (e.g. quitting right after a purchase).
	if _save_left >= 0.0:
		save_game()
