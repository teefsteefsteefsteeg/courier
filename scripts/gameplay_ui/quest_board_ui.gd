class_name QuestBoardUI
extends CanvasLayer
## Delivery-contract window. Opens when any QuestBoard (group "quest_board") emits
## `opened`. Lists the board's quests with destination, reward and an Accept button.
## Freezes the interacting player's input while open and joins the "ui_modal" group,
## so World/UI (prompt, dialogue, journal) stand down until it closes.

signal opened
signal contract_accepted(quest_id: StringName)
signal closed

@export var quest_manager: QuestManager

@onready var root_panel: Control = %BoardPanel
@onready var title_label: Label = %BoardTitle
@onready var entry_list: VBoxContainer = %EntryList
@onready var feedback_label: Label = %FeedbackLabel
@onready var close_button: Button = %CloseButton

## quest_id -> Accept button for the currently shown list (read by tests).
var accept_buttons: Dictionary[StringName, Button] = {}
var _board: QuestBoard = null
var _player: PlayerController = null


func _ready() -> void:
	root_panel.visible = false
	close_button.pressed.connect(close)
	_connect.call_deferred()


func _connect() -> void:
	if quest_manager == null:
		quest_manager = QuestManager.find(get_tree())
	if quest_manager != null:
		quest_manager.quest_state_changed.connect(_on_quest_state_changed)
	for node in get_tree().get_nodes_in_group(QuestBoard.GROUP):
		var board := node as QuestBoard
		if board != null and not board.opened.is_connected(open):
			board.opened.connect(open)


func is_open() -> bool:
	return root_panel.visible


func open(board: QuestBoard, interactor: Node) -> void:
	if quest_manager == null:
		return
	_board = board
	_player = interactor as PlayerController
	if _player != null:
		_player.input_enabled = false
	title_label.text = board.board_name
	feedback_label.text = ""
	_rebuild()
	root_panel.visible = true
	add_to_group(QuestJournal.MODAL_GROUP)
	_focus_first_button()
	opened.emit()


func close() -> void:
	if not is_open():
		return
	root_panel.visible = false
	remove_from_group(QuestJournal.MODAL_GROUP)
	_board = null
	if _player != null:
		# Deferred so the key press that closed the window cannot re-open it this frame.
		_player.set_deferred(&"input_enabled", true)
		_player = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child in entry_list.get_children():
		entry_list.remove_child(child)
		child.queue_free()
	accept_buttons.clear()
	if _board == null:
		return
	for definition in _board.get_offered_quests(quest_manager):
		entry_list.add_child(_build_entry(definition))


func _build_entry(definition: QuestDefinition) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ContractPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	panel.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	title.theme_type_variation = &"ContractTitle"
	title.text = definition.title
	text.add_child(title)
	var description := Label.new()
	description.text = definition.description
	description.theme_type_variation = &"ContractDetail"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 420
	text.add_child(description)
	var package_name := definition.package.package_name if definition.package != null else "-"
	var details := Label.new()
	details.theme_type_variation = &"ContractDetail"
	details.text = "Package: %s\nDeliver to: %s, %s\nReward: %s" % [
		package_name, definition.recipient_name, definition.destination_name,
		definition.reward.describe() if definition.reward != null else "None"]
	text.add_child(details)

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.custom_minimum_size.x = 190
	row.add_child(side)
	var status := quest_manager.get_status(definition.quest_id)
	var status_label := Label.new()
	status_label.theme_type_variation = &"ContractDetail"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = _status_text(status)
	side.add_child(status_label)
	var button := Button.new()
	button.text = "Accept"
	var check := quest_manager.can_accept(definition.quest_id)
	button.disabled = check != QuestManager.AcceptResult.OK
	if status == QuestState.Status.AVAILABLE and check != QuestManager.AcceptResult.OK:
		button.tooltip_text = QuestManager.accept_result_text(check)
		status_label.text = QuestManager.accept_result_text(check)
	button.visible = status == QuestState.Status.AVAILABLE
	button.pressed.connect(_on_accept_pressed.bind(definition.quest_id))
	side.add_child(button)
	accept_buttons[definition.quest_id] = button
	return panel


func _status_text(status: QuestState.Status) -> String:
	match status:
		QuestState.Status.AVAILABLE: return "Available"
		QuestState.Status.ACCEPTED: return "Accepted"
		QuestState.Status.ACTIVE: return "In progress"
		QuestState.Status.COMPLETED: return "Completed"
		QuestState.Status.FAILED: return "Failed"
		QuestState.Status.REWARDED: return "Delivered ✓"
	return ""


func _on_accept_pressed(quest_id: StringName) -> void:
	var result := quest_manager.accept_quest(quest_id)
	if result == QuestManager.AcceptResult.OK:
		var definition := quest_manager.get_definition(quest_id)
		feedback_label.text = "Contract accepted: %s" % definition.title
		var first := quest_manager.get_current_objective(quest_id)
		if first != null:
			feedback_label.text += "\nFirst: %s" % first.description
		contract_accepted.emit(quest_id)
	else:
		feedback_label.text = QuestManager.accept_result_text(result)
	_rebuild()
	_focus_first_button()


func _focus_first_button() -> void:
	for id in accept_buttons:
		var button := accept_buttons[id]
		if button.visible and not button.disabled:
			button.grab_focus.call_deferred()
			return
	close_button.grab_focus.call_deferred()


func _on_quest_state_changed(_quest_id: StringName, _new: QuestState.Status, _old: QuestState.Status) -> void:
	if is_open():
		_rebuild()
