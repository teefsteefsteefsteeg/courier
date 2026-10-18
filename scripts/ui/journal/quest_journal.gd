class_name QuestJournal
extends CanvasLayer
## Courier's Journal: a two-page book listing deliveries in progress and the
## archive (completed and failed), with the selected delivery's route,
## notes, objective checklist and reward.
##
## Data comes from JournalData: the gameplay QuestManager when one is in the
## scene, otherwise optional preview entries. While open, the player's input is
## paused and the journal joins the "ui_modal" group so other UI ignores input.
## HUD layers in the "hidden_by_journal" group (interaction prompt, location
## banner) are hidden while open and restored to their prior visibility on close.

signal opened
signal closed
signal entry_selected(id: StringName)

enum Tab { IN_PROGRESS, ARCHIVE }

const MODAL_GROUP := &"ui_modal"
const HIDDEN_WHILE_OPEN_GROUP := &"hidden_by_journal"
const WATCHED_SIGNALS: Array[StringName] = [&"quest_state_changed", &"objective_progressed", &"objective_completed", &"quest_failed"]
const STATUS_TEXT := {
	JournalData.STATUS_ACTIVE: "In progress",
	JournalData.STATUS_COMPLETED: "Delivered",
	JournalData.STATUS_FAILED: "Failed",
}
const STATUS_COLOR := {
	JournalData.STATUS_ACTIVE: Color(0.62, 0.38, 0.04),
	JournalData.STATUS_COMPLETED: Color(0.18, 0.45, 0.2),
	JournalData.STATUS_FAILED: Color(0.66, 0.15, 0.12),
}
const INK := Color(0.25, 0.16, 0.08)
const INK_FADED := Color(0.25, 0.16, 0.08, 0.55)

@export var player: PlayerController
@export var toggle_action: StringName = &"toggle_journal"
## Show preview entries when no quest system is present (layout and playtesting).
@export var use_sample_data_when_unconnected: bool = true

@onready var root_control: Control = %Root
@onready var hint_label: Label = %HintLabel
@onready var close_hint: Label = %CloseHint
@onready var tab_active: Button = %TabActive
@onready var tab_archive: Button = %TabArchive
@onready var quest_list: VBoxContainer = %QuestList
@onready var empty_label: Label = %EmptyLabel
@onready var detail_placeholder: Label = %DetailPlaceholder
@onready var detail_content: Control = %DetailContent
@onready var detail_title: Label = %DetailTitle
@onready var status_label: Label = %StatusLabel
@onready var route_label: Label = %RouteLabel
@onready var description_label: Label = %DescriptionLabel
@onready var objectives_box: VBoxContainer = %ObjectivesBox
@onready var reward_label: Label = %RewardLabel
@onready var source_label: Label = %SourceLabel

var entries: Array[Dictionary] = []
var current_tab: Tab = Tab.IN_PROGRESS
var _selected_id: StringName = &""
var _manager: Node = null
var _player_input_was_enabled: bool = true
var _refresh_queued: bool = false
## Instance id -> visibility before open() hid it.
var _hidden_hud: Dictionary[int, bool] = {}
var _tab_group := ButtonGroup.new()
var _entry_group := ButtonGroup.new()


func _ready() -> void:
	root_control.visible = false
	tab_active.button_group = _tab_group
	tab_archive.button_group = _tab_group
	tab_active.button_pressed = true
	tab_active.pressed.connect(show_tab.bind(Tab.IN_PROGRESS))
	tab_archive.pressed.connect(show_tab.bind(Tab.ARCHIVE))
	hint_label.text = "[%s] Journal" % InputHints.key_for(toggle_action)
	close_hint.text = "[%s] Close" % InputHints.key_for(toggle_action)
	InputPromptLabel.attach(hint_label)
	InputPromptLabel.attach(close_hint)
	_find_manager.call_deferred()


func _process(_delta: float) -> void:
	# The bottom-centre hint sits under the dialogue box; it stands down while one is open.
	var shown := not is_open() and get_tree().get_node_count_in_group(DialogueBox.OPEN_GROUP) == 0
	if hint_label.visible != shown:
		hint_label.visible = shown


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		toggle()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return root_control.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	# The journal is only in MODAL_GROUP while open, so any member is another window (e.g. the quest board).
	if is_open() or get_tree().get_node_count_in_group(MODAL_GROUP) > 0:
		return
	refresh()
	root_control.visible = true
	hint_label.visible = false
	add_to_group(MODAL_GROUP)
	if player != null:
		_player_input_was_enabled = player.input_enabled
		player.input_enabled = false
	_hide_hud()
	_focus_selected()
	opened.emit()


func close() -> void:
	if not is_open():
		return
	root_control.visible = false
	hint_label.visible = true
	remove_from_group(MODAL_GROUP)
	if player != null:
		player.input_enabled = _player_input_was_enabled
	_restore_hud()
	closed.emit()


## Re-reads entries from the data source and redraws both pages.
func refresh() -> void:
	_find_manager()
	if _manager != null:
		set_entries(JournalData.from_quest_manager(_manager, _npc_name))
		source_label.visible = false
	elif use_sample_data_when_unconnected:
		set_entries(JournalData.sample_entries())
		source_label.text = "Preview entries: no quest system is running in this scene."
		source_label.visible = true
	else:
		set_entries([])
		source_label.visible = false


func set_entries(new_entries: Array[Dictionary]) -> void:
	entries = new_entries
	_rebuild_list()


func show_tab(tab: Tab) -> void:
	current_tab = tab
	var tab_button := tab_active if tab == Tab.IN_PROGRESS else tab_archive
	tab_button.button_pressed = true
	_rebuild_list()


func select_entry(id: StringName) -> void:
	_selected_id = id
	var entry := _find_entry(id)
	for button: Button in quest_list.get_children():
		button.set_pressed_no_signal(button.get_meta(&"entry_id") == id)
	_show_details(entry)
	if not entry.is_empty():
		entry_selected.emit(id)


func get_selected_id() -> StringName:
	return _selected_id


func get_visible_entries() -> Array[Dictionary]:
	var archived := current_tab == Tab.ARCHIVE
	var shown: Array[Dictionary] = []
	shown.assign(entries.filter(func(e: Dictionary) -> bool: return JournalData.is_archived(e) == archived))
	return shown


func _rebuild_list() -> void:
	var archived_count := entries.filter(func(e: Dictionary) -> bool: return JournalData.is_archived(e)).size()
	tab_active.text = "In Progress (%d)" % (entries.size() - archived_count)
	tab_archive.text = "Archive (%d)" % archived_count

	for child in quest_list.get_children():
		quest_list.remove_child(child)
		child.queue_free()
	var shown := get_visible_entries()
	for entry in shown:
		quest_list.add_child(_make_entry_button(entry))

	empty_label.visible = shown.is_empty()
	empty_label.text = "No deliveries in progress.\nCheck the board at the post office." \
			if current_tab == Tab.IN_PROGRESS else "Nothing archived yet."
	var keep_selection := shown.any(func(e: Dictionary) -> bool: return e["id"] == _selected_id)
	select_entry(_selected_id if keep_selection else (shown[0]["id"] if not shown.is_empty() else &""))


func _make_entry_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _entry_group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 46)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.set_meta(&"entry_id", entry["id"])
	var status: String = entry.get("status", JournalData.STATUS_ACTIVE)
	button.text = entry.get("title", "?")
	if status != JournalData.STATUS_ACTIVE:
		button.text += "  ·  %s" % STATUS_TEXT[status]
		button.add_theme_color_override(&"font_color", STATUS_COLOR[status])
	button.pressed.connect(select_entry.bind(entry["id"]))
	return button


func _show_details(entry: Dictionary) -> void:
	detail_placeholder.visible = entry.is_empty()
	detail_content.visible = not entry.is_empty()
	if entry.is_empty():
		return
	var status: String = entry.get("status", JournalData.STATUS_ACTIVE)
	detail_title.text = entry.get("title", "")
	status_label.text = STATUS_TEXT[status].to_upper()
	status_label.add_theme_color_override(&"font_color", STATUS_COLOR[status])

	var route: PackedStringArray = []
	if not str(entry.get("giver", "")).is_empty():
		route.append("From %s" % entry["giver"])
	var recipient := str(entry.get("recipient", ""))
	var destination := str(entry.get("destination", ""))
	if not recipient.is_empty():
		route.append("To %s%s" % [recipient, (", " + destination) if not destination.is_empty() else ""])
	elif not destination.is_empty():
		route.append("To %s" % destination)
	route_label.text = "  ·  ".join(route)
	route_label.visible = not route.is_empty()
	description_label.text = entry.get("description", "")

	for child in objectives_box.get_children():
		objectives_box.remove_child(child)
		child.queue_free()
	for objective: Dictionary in entry.get("objectives", []):
		objectives_box.add_child(_make_objective_row(objective))

	var reward := str(entry.get("reward", ""))
	reward_label.text = "Reward: %s" % reward
	reward_label.visible = not reward.is_empty()


func _make_objective_row(objective: Dictionary) -> Control:
	var done: bool = objective.get("done", false)
	var current: bool = objective.get("current", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)

	var box := Panel.new()
	box.custom_minimum_size = Vector2(18, 18)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.border_color = Color(0.78, 0.5, 0.12) if current else INK
	style.bg_color = Color(0.2, 0.45, 0.22) if done else Color(0, 0, 0, 0)
	box.add_theme_stylebox_override(&"panel", style)
	row.add_child(box)

	var label := Label.new()
	label.theme_type_variation = &"InkLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var required: int = objective.get("required", 1)
	label.text = str(objective.get("text", ""))
	if required > 1:
		label.text += " (%d/%d)" % [objective.get("progress", 0), required]
	label.add_theme_color_override(&"font_color", INK_FADED if done else INK)
	row.add_child(label)
	row.set_meta(&"done", done)
	row.set_meta(&"current", current)
	return row


func _find_entry(id: StringName) -> Dictionary:
	for entry in entries:
		if entry["id"] == id:
			return entry
	return {}


func _focus_selected() -> void:
	for button: Button in quest_list.get_children():
		if button.button_pressed:
			button.grab_focus()
			return
	tab_active.grab_focus()


func _hide_hud() -> void:
	_hidden_hud.clear()
	for node in get_tree().get_nodes_in_group(HIDDEN_WHILE_OPEN_GROUP):
		if node is CanvasLayer or node is CanvasItem:
			_hidden_hud[node.get_instance_id()] = node.get(&"visible")
			node.set(&"visible", false)


func _restore_hud() -> void:
	for id in _hidden_hud:
		var node := instance_from_id(id)
		if node != null:
			node.set(&"visible", _hidden_hud[id])
	_hidden_hud.clear()


func _npc_name(npc_id: StringName) -> String:
	return JournalData.npc_display_name(get_tree(), npc_id)


## Finds the quest manager (it may be spawned after the journal) and subscribes once.
func _find_manager() -> void:
	if _manager != null and is_instance_valid(_manager):
		return
	_manager = JournalData.find_quest_manager(get_tree())
	if _manager == null:
		return
	for info: Dictionary in _manager.get_signal_list():
		if StringName(info["name"]) in WATCHED_SIGNALS:
			_manager.connect(info["name"], _queue_refresh.unbind((info["args"] as Array).size()))


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	(func() -> void:
		_refresh_queued = false
		if is_open():
			refresh()
	).call_deferred()
