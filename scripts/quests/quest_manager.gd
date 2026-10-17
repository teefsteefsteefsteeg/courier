class_name QuestManager
extends Node
## Owns all quest runtime state. Gameplay objects report events (talked, picked up,
## reached, delivered) and the manager advances objectives, enforces rules, and
## grants rewards exactly once. UI only listens to signals and calls queries.
##
## Rules (MVP):
## - A quest can be accepted only while AVAILABLE (no duplicates).
## - Only one delivery quest may be ACCEPTED/ACTIVE/COMPLETED-unrewarded at a time.
## - Objectives complete in order. ACCEPTED becomes ACTIVE on first objective progress.
## - COMPLETED grants the reward immediately and becomes REWARDED; grant is idempotent.

signal quest_state_changed(quest_id: StringName, new_status: QuestState.Status, old_status: QuestState.Status)
signal quest_accepted(quest_id: StringName)
signal quest_activated(quest_id: StringName)
signal objective_progressed(quest_id: StringName, objective_index: int, progress: int, required: int)
signal objective_completed(quest_id: StringName, objective_index: int)
signal quest_completed(quest_id: StringName)
signal quest_failed(quest_id: StringName, reason: String)
signal quest_rewarded(quest_id: StringName, reward: QuestReward)
## quest_id is &"" when the delivery slot becomes free.
signal active_delivery_changed(quest_id: StringName)
signal delivery_rejected(quest_id: StringName, npc_id: StringName, result: DeliveryResult)

enum AcceptResult { OK, UNKNOWN_QUEST, NOT_AVAILABLE, ALREADY_ACCEPTED, DELIVERY_IN_PROGRESS }
enum DeliveryResult { OK, NO_PACKAGE, UNKNOWN_QUEST, QUEST_NOT_ACTIVE, WRONG_RECIPIENT, NOT_READY }

const GROUP := &"quest_manager"

@export var quest_definitions: Array[QuestDefinition] = []
@export var wallet: CourierWallet

var _definitions: Dictionary[StringName, QuestDefinition] = {}
var _states: Dictionary[StringName, QuestState] = {}
var _quest_order: Array[StringName] = []
var _active_delivery_id: StringName = &""


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for definition in quest_definitions:
		register_quest(definition)
	if wallet == null:
		wallet = CourierWallet.find(get_tree())


static func find(tree: SceneTree) -> QuestManager:
	return tree.get_first_node_in_group(GROUP) as QuestManager


# --- registration & queries ---------------------------------------------------

func register_quest(definition: QuestDefinition) -> bool:
	if definition == null or definition.quest_id == &"":
		push_error("QuestManager: quest without quest_id")
		return false
	if _definitions.has(definition.quest_id):
		push_warning("QuestManager: duplicate quest_id %s ignored" % definition.quest_id)
		return false
	_definitions[definition.quest_id] = definition
	var state := QuestState.new()
	state.quest_id = definition.quest_id
	state.objective_progress.resize(definition.objectives.size())
	_states[definition.quest_id] = state
	_quest_order.append(definition.quest_id)
	return true


func get_quest_ids() -> Array[StringName]:
	return _quest_order.duplicate()


func get_definition(quest_id: StringName) -> QuestDefinition:
	return _definitions.get(quest_id)


func get_state(quest_id: StringName) -> QuestState:
	return _states.get(quest_id)


func get_status(quest_id: StringName) -> QuestState.Status:
	var state := get_state(quest_id)
	return state.status if state != null else QuestState.Status.AVAILABLE


func get_available_quests() -> Array[QuestDefinition]:
	var result: Array[QuestDefinition] = []
	for id in _quest_order:
		if _states[id].status == QuestState.Status.AVAILABLE:
			result.append(_definitions[id])
	return result


func get_in_progress_quests() -> Array[QuestDefinition]:
	var result: Array[QuestDefinition] = []
	for id in _quest_order:
		if _states[id].is_in_progress():
			result.append(_definitions[id])
	return result


func get_active_delivery_id() -> StringName:
	return _active_delivery_id


func get_current_objective(quest_id: StringName) -> QuestObjective:
	var state := get_state(quest_id)
	if state == null or not state.is_in_progress():
		return null
	var objectives := _definitions[quest_id].objectives
	return objectives[state.objective_index] if state.objective_index < objectives.size() else null


## In-progress quests whose package goes to npc_id.
func get_quests_awaiting_recipient(npc_id: StringName) -> Array[QuestDefinition]:
	var result: Array[QuestDefinition] = []
	for definition in get_in_progress_quests():
		if definition.get_recipient_id() == npc_id:
			result.append(definition)
	return result


## Rewarded quests whose package went to npc_id (most recent last).
func get_rewarded_quests_for_recipient(npc_id: StringName) -> Array[QuestDefinition]:
	var result: Array[QuestDefinition] = []
	for id in _quest_order:
		if _states[id].status == QuestState.Status.REWARDED and _definitions[id].get_recipient_id() == npc_id:
			result.append(_definitions[id])
	return result


## True when an in-progress quest's current objective is to pick up package_id.
func is_package_pickup_pending(package_id: StringName) -> bool:
	for definition in get_in_progress_quests():
		var objective := get_current_objective(definition.quest_id)
		if objective != null and objective.type == QuestObjective.Type.PICK_UP_PACKAGE and objective.target_id == package_id:
			return true
	return false


# --- acceptance ---------------------------------------------------------------

func can_accept(quest_id: StringName) -> AcceptResult:
	var state := get_state(quest_id)
	if state == null:
		return AcceptResult.UNKNOWN_QUEST
	if state.is_in_progress():
		return AcceptResult.ALREADY_ACCEPTED
	if state.status != QuestState.Status.AVAILABLE:
		return AcceptResult.NOT_AVAILABLE
	if _definitions[quest_id].is_delivery and _active_delivery_id != &"":
		return AcceptResult.DELIVERY_IN_PROGRESS
	return AcceptResult.OK


func accept_quest(quest_id: StringName) -> AcceptResult:
	var result := can_accept(quest_id)
	if result != AcceptResult.OK:
		return result
	var state := _states[quest_id]
	state.objective_index = 0
	state.objective_progress.fill(0)
	state.fail_reason = ""
	if _definitions[quest_id].is_delivery:
		_set_active_delivery(quest_id)
	_set_status(state, QuestState.Status.ACCEPTED)
	quest_accepted.emit(quest_id)
	return result


static func accept_result_text(result: AcceptResult) -> String:
	match result:
		AcceptResult.OK: return "Accepted"
		AcceptResult.UNKNOWN_QUEST: return "Unknown contract"
		AcceptResult.NOT_AVAILABLE: return "No longer available"
		AcceptResult.ALREADY_ACCEPTED: return "Already accepted"
		AcceptResult.DELIVERY_IN_PROGRESS: return "Finish your current delivery first"
	return "?"


# --- gameplay events ----------------------------------------------------------

## Returns the objective that completed, or null if this talk advanced nothing.
func notify_talked_to(npc_id: StringName) -> QuestObjective:
	return _advance_matching(QuestObjective.Type.TALK_TO_NPC, npc_id)


func notify_package_picked_up(package_id: StringName) -> QuestObjective:
	return _advance_matching(QuestObjective.Type.PICK_UP_PACKAGE, package_id)


func notify_destination_reached(destination_id: StringName) -> QuestObjective:
	return _advance_matching(QuestObjective.Type.REACH_DESTINATION, destination_id)


## Validates and performs a delivery. On OK the caller must remove the package.
func try_deliver(npc_id: StringName, package: PackageInstance) -> DeliveryResult:
	var result := _validate_delivery(npc_id, package)
	if result != DeliveryResult.OK:
		delivery_rejected.emit(package.get_quest_id() if package != null else &"", npc_id, result)
		return result
	_advance_objective(_states[package.get_quest_id()], 1)
	return result


func _validate_delivery(npc_id: StringName, package: PackageInstance) -> DeliveryResult:
	if package == null:
		return DeliveryResult.NO_PACKAGE
	var quest_id := package.get_quest_id()
	var state := get_state(quest_id)
	if state == null:
		return DeliveryResult.UNKNOWN_QUEST
	if not state.is_in_progress():
		return DeliveryResult.QUEST_NOT_ACTIVE
	if package.get_recipient_id() != npc_id:
		return DeliveryResult.WRONG_RECIPIENT
	var objective := get_current_objective(quest_id)
	if objective == null or objective.type != QuestObjective.Type.DELIVER_PACKAGE or objective.target_id != npc_id:
		return DeliveryResult.NOT_READY
	return DeliveryResult.OK


# --- failure & rewards --------------------------------------------------------

func fail_quest(quest_id: StringName, reason: String = "") -> bool:
	var state := get_state(quest_id)
	if state == null or not state.is_in_progress():
		return false
	state.fail_reason = reason
	# Free the slot first so listeners of quest_state_changed see a consistent world.
	_release_delivery_slot(quest_id)
	_set_status(state, QuestState.Status.FAILED)
	quest_failed.emit(quest_id, reason)
	return true


## Makes a FAILED quest available again (retry).
func reset_failed_quest(quest_id: StringName) -> bool:
	var state := get_state(quest_id)
	if state == null or state.status != QuestState.Status.FAILED:
		return false
	state.objective_index = 0
	state.objective_progress.fill(0)
	_set_status(state, QuestState.Status.AVAILABLE)
	return true


## Grants the reward for a COMPLETED quest. Returns false if already granted or not completed.
func grant_reward(quest_id: StringName) -> bool:
	var state := get_state(quest_id)
	if state == null or state.reward_granted or state.status != QuestState.Status.COMPLETED:
		return false
	state.reward_granted = true
	var reward := _definitions[quest_id].reward
	if reward != null and wallet != null:
		wallet.add_gold(reward.gold)
		wallet.add_reputation(reward.reputation)
	elif reward != null:
		push_warning("QuestManager: no CourierWallet; reward for %s not paid" % quest_id)
	_release_delivery_slot(quest_id)
	_set_status(state, QuestState.Status.REWARDED)
	quest_rewarded.emit(quest_id, reward)
	return true


# --- internals ----------------------------------------------------------------

func _advance_matching(type: QuestObjective.Type, target_id: StringName) -> QuestObjective:
	for id in _quest_order:
		var objective := get_current_objective(id)
		if objective != null and objective.type == type and objective.target_id == target_id:
			_advance_objective(_states[id], 1)
			return objective
	return null


func _advance_objective(state: QuestState, amount: int) -> void:
	var definition := _definitions[state.quest_id]
	var index := state.objective_index
	var objective := definition.objectives[index]
	if state.status == QuestState.Status.ACCEPTED:
		_set_status(state, QuestState.Status.ACTIVE)
		quest_activated.emit(state.quest_id)
	state.objective_progress[index] = mini(state.objective_progress[index] + amount, objective.required_count)
	objective_progressed.emit(state.quest_id, index, state.objective_progress[index], objective.required_count)
	if state.objective_progress[index] < objective.required_count:
		return
	state.objective_index += 1
	objective_completed.emit(state.quest_id, index)
	if state.objective_index >= definition.objectives.size():
		_set_status(state, QuestState.Status.COMPLETED)
		quest_completed.emit(state.quest_id)
		grant_reward(state.quest_id)


func _set_status(state: QuestState, new_status: QuestState.Status) -> void:
	if state.status == new_status:
		return
	var old := state.status
	state.status = new_status
	quest_state_changed.emit(state.quest_id, new_status, old)


func _set_active_delivery(quest_id: StringName) -> void:
	if _active_delivery_id == quest_id:
		return
	_active_delivery_id = quest_id
	active_delivery_changed.emit(quest_id)


func _release_delivery_slot(quest_id: StringName) -> void:
	if _active_delivery_id == quest_id:
		_set_active_delivery(&"")
