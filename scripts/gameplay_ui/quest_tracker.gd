class_name QuestTracker
extends Control
## Shows the active delivery: title, current objective and destination.
## Phase 5F: the header reads the delivery stage and step ("ACTIVE DELIVERY · STEP 2/3",
## "READY TO DELIVER", "PACKAGE DROPPED"), a reward line is shown, and the objective
## flashes briefly when it changes.

const HIGHLIGHT_COLOR := Color(1.0, 0.86, 0.4)

@export var quest_manager: QuestManager
## Optional; enables the carried/dropped package stages. GameplayHUD binds the player's.
@export var carrier: PackageCarrier
@export_range(0.1, 5.0, 0.1, "suffix:s") var highlight_time: float = 1.2

@onready var header_label: Label = %Header
@onready var title_label: Label = %TrackerTitle
@onready var objective_label: Label = %TrackerObjective
@onready var destination_label: Label = %TrackerDestination
@onready var reward_label: Label = %TrackerReward

## Quest currently shown, &"" when hidden.
var shown_quest_id: StringName = &""
## Times the objective line changed while the same quest stayed on screen (read by tests).
var objective_changes: int = 0
var _highlight_left: float = 0.0


func _ready() -> void:
	visible = false
	_connect.call_deferred()


func _connect() -> void:
	if quest_manager == null:
		quest_manager = QuestManager.find(get_tree())
	if quest_manager == null:
		return
	quest_manager.quest_state_changed.connect(func(_a, _b, _c): refresh())
	quest_manager.objective_progressed.connect(func(_a, _b, _c, _d): refresh())
	quest_manager.objective_completed.connect(func(_a, _b): refresh())
	quest_manager.active_delivery_changed.connect(func(_a): refresh())
	refresh()


func bind_carrier(new_carrier: PackageCarrier) -> void:
	if carrier != null and carrier.carried_package_changed.is_connected(_on_carried_package_changed):
		carrier.carried_package_changed.disconnect(_on_carried_package_changed)
	carrier = new_carrier
	if carrier != null:
		carrier.carried_package_changed.connect(_on_carried_package_changed)
	if quest_manager != null:
		refresh()


func _process(delta: float) -> void:
	if _highlight_left <= 0.0:
		return
	_highlight_left = maxf(_highlight_left - delta, 0.0)
	objective_label.modulate = Color.WHITE.lerp(HIGHLIGHT_COLOR, _highlight_left / highlight_time)


func is_highlighting() -> bool:
	return _highlight_left > 0.0


func refresh() -> void:
	if quest_manager == null:
		return
	var quest_id := quest_manager.get_active_delivery_id()
	if quest_id == &"":
		var in_progress := quest_manager.get_in_progress_quests()
		quest_id = in_progress[0].quest_id if not in_progress.is_empty() else &""
	if quest_id == &"":
		visible = false
		shown_quest_id = &""
		return
	var definition := quest_manager.get_definition(quest_id)
	var state := quest_manager.get_state(quest_id)
	var objective := quest_manager.get_current_objective(quest_id)
	title_label.text = definition.title
	var objective_text := ""
	if objective != null:
		var progress := ""
		if objective.required_count > 1:
			progress = " (%d/%d)" % [state.objective_progress[state.objective_index], objective.required_count]
		objective_text = "▸ %s%s" % [objective.description, progress]
	else:
		objective_text = "▸ %s" % QuestState.status_name(state.status).capitalize()
	if quest_id == shown_quest_id and objective_text != objective_label.text:
		objective_changes += 1
		_highlight_left = highlight_time
		objective_label.modulate = HIGHLIGHT_COLOR
	objective_label.text = objective_text
	header_label.text = get_header_text(quest_id)
	destination_label.text = "To: %s, %s" % [definition.recipient_name, definition.destination_name]
	reward_label.text = "Reward: %s" % definition.reward.describe() if definition.reward != null else ""
	reward_label.visible = definition.reward != null
	shown_quest_id = quest_id
	visible = true


## Stage + step line for quest_id, e.g. "ACTIVE DELIVERY · STEP 2/3".
func get_header_text(quest_id: StringName) -> String:
	var definition := quest_manager.get_definition(quest_id)
	var state := quest_manager.get_state(quest_id)
	if definition == null or state == null:
		return ""
	var stage := "ACTIVE DELIVERY"
	var objective := quest_manager.get_current_objective(quest_id)
	if state.status == QuestState.Status.ACCEPTED:
		stage = "CONTRACT ACCEPTED"
	if objective != null and objective.type != QuestObjective.Type.PICK_UP_PACKAGE \
			and objective.type != QuestObjective.Type.TALK_TO_NPC and _past_pickup(definition, state.objective_index):
		if _carrying(quest_id):
			if objective.type == QuestObjective.Type.DELIVER_PACKAGE:
				stage = "READY TO DELIVER"
		elif carrier != null:
			stage = "PACKAGE DROPPED"
	var total := definition.objectives.size()
	if total <= 1 or objective == null:
		return stage
	return "%s · STEP %d/%d" % [stage, mini(state.objective_index + 1, total), total]


func _carrying(quest_id: StringName) -> bool:
	return carrier != null and carrier.is_carrying() and carrier.get_package().get_quest_id() == quest_id


## True when a PICK_UP_PACKAGE objective comes before objective_index (the courier
## should be holding the package by now).
static func _past_pickup(definition: QuestDefinition, objective_index: int) -> bool:
	for i in mini(objective_index, definition.objectives.size()):
		if definition.objectives[i].type == QuestObjective.Type.PICK_UP_PACKAGE:
			return true
	return false


func _on_carried_package_changed(_package: PackageInstance) -> void:
	refresh()
