class_name QuestTracker
extends Control
## Shows the active delivery: title, current objective and destination.

@export var quest_manager: QuestManager

@onready var title_label: Label = %TrackerTitle
@onready var objective_label: Label = %TrackerObjective
@onready var destination_label: Label = %TrackerDestination


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


func refresh() -> void:
	var quest_id := quest_manager.get_active_delivery_id()
	if quest_id == &"":
		var in_progress := quest_manager.get_in_progress_quests()
		quest_id = in_progress[0].quest_id if not in_progress.is_empty() else &""
	if quest_id == &"":
		visible = false
		return
	var definition := quest_manager.get_definition(quest_id)
	var state := quest_manager.get_state(quest_id)
	var objective := quest_manager.get_current_objective(quest_id)
	title_label.text = definition.title
	if objective != null:
		var progress := ""
		if objective.required_count > 1:
			progress = " (%d/%d)" % [state.objective_progress[state.objective_index], objective.required_count]
		objective_label.text = "▸ %s%s" % [objective.description, progress]
	else:
		objective_label.text = "▸ %s" % QuestState.status_name(state.status).capitalize()
	destination_label.text = "To: %s, %s" % [definition.recipient_name, definition.destination_name]
	visible = true
