class_name DialogueBox
extends CanvasLayer
## Bottom-of-screen dialogue panel with a speaker plate, portrait and typewriter text.
##
## It binds itself to every NPC in the tree through the NPC's `spoke` signal, so
## any system that makes an NPC speak (the Phase 1 line cycler, quest behaviours)
## shows up here without coupling to this UI. Scripted sequences can call
## `play_lines()` directly.
##
## Controls while open: interact / ui_accept finishes the typewriter, then moves to
## the next queued line. With nothing queued, interact passes through to the player
## so talking to the NPC again continues the conversation. ui_cancel closes. Walking
## away from the speaker closes the box.

signal line_started(speaker: String, text: String)
signal line_completed(speaker: String, text: String)
signal closed

const DEFAULT_COLOR := Color(0.55, 0.5, 0.65)
## While any node is in this group (e.g. the open quest journal), dialogue ignores input.
const MODAL_GROUP := &"ui_modal"
## Joined while the box is open; bottom-centre hints (the journal's) stand down meanwhile.
const OPEN_GROUP := &"dialogue_open"

@export var detector: InteractionDetector
@export var prompt: InteractionPrompt
@export var advance_action: StringName = &"interact"
@export_range(5.0, 400.0, 1.0, "suffix:chars/s") var characters_per_second: float = 55.0
## Hide the NPC's 3D speech bubble when its line is shown here instead.
@export var hide_world_bubbles: bool = true

@onready var box: Control = %Box
@onready var name_label: Label = %NameLabel
@onready var text_label: Label = %TextLabel
@onready var hint_label: Label = %HintLabel
@onready var portrait: Panel = %Portrait
@onready var portrait_initial: Label = %PortraitInitial

var speaker: String = ""
var _source: Node = null
var _queue: Array[String] = []
var _typing: bool = false
var _shown_chars: float = 0.0
var _portrait_style := StyleBoxFlat.new()
var _bound_npcs: Dictionary[int, bool] = {}


func _ready() -> void:
	box.visible = false
	# The open journal covers the screen; hide this layer meanwhile (it restores it after).
	add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	box.add_to_group(InputPrompt.AVOID_GROUP)
	InputPromptLabel.attach(hint_label)
	_portrait_style.set_corner_radius_all(10)
	_portrait_style.set_border_width_all(3)
	_portrait_style.border_color = Color(0.95, 0.78, 0.35)
	portrait.add_theme_stylebox_override(&"panel", _portrait_style)
	if detector != null:
		detector.focus_changed.connect(_on_focus_changed)
	get_tree().node_added.connect(_on_node_added)
	_bind_existing_npcs.call_deferred()


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown_chars += characters_per_second * delta
	text_label.visible_characters = int(_shown_chars)
	if text_label.visible_characters >= text_label.get_total_character_count():
		_finish_line()


func _input(event: InputEvent) -> void:
	if not is_open() or get_tree().get_node_count_in_group(MODAL_GROUP) > 0:
		return
	var advance := event.is_action_pressed(advance_action)
	var accept := event.is_action_pressed(&"ui_accept")
	if advance or accept:
		if _typing:
			skip_typing()
		elif not _queue.is_empty():
			_show_line(_queue.pop_front())
		elif advance and _source_still_focused():
			return  # Let the player re-interact with the NPC for its next line.
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Connects an NPC so its spoken lines appear in this box. Safe to call repeatedly.
func bind_npc(npc: NPC) -> void:
	if _bound_npcs.has(npc.get_instance_id()):
		return
	_bound_npcs[npc.get_instance_id()] = true
	npc.spoke.connect(_on_npc_spoke.bind(npc))


## Shows one line immediately, replacing whatever was displayed.
func show_line(speaker_name: String, text: String, color: Color = DEFAULT_COLOR, source: Node = null) -> void:
	play_lines(speaker_name, PackedStringArray([text]), color, source)


## Plays several lines in order; the player advances with interact / ui_accept.
func play_lines(speaker_name: String, lines: PackedStringArray, color: Color = DEFAULT_COLOR, source: Node = null) -> void:
	if lines.is_empty():
		return
	speaker = speaker_name
	_source = source
	_queue.assign(Array(lines))
	name_label.text = speaker_name
	portrait_initial.text = speaker_name.split(" ")[-1].left(1).to_upper() if not speaker_name.is_empty() else "?"
	_portrait_style.bg_color = color
	box.visible = true
	add_to_group(OPEN_GROUP)
	if prompt != null:
		prompt.set_suppressed(true)
	_show_line(_queue.pop_front())


func close() -> void:
	if not is_open():
		return
	box.visible = false
	remove_from_group(OPEN_GROUP)
	_typing = false
	_queue.clear()
	_source = null
	speaker = ""
	if prompt != null:
		prompt.set_suppressed(false)
	closed.emit()


func skip_typing() -> void:
	if _typing:
		_finish_line()


func is_open() -> bool:
	return box.visible


func is_typing() -> bool:
	return _typing


func get_text() -> String:
	return text_label.text


func get_queued_count() -> int:
	return _queue.size()


func _show_line(text: String) -> void:
	text_label.text = text
	text_label.visible_characters = 0
	_shown_chars = 0.0
	_typing = true
	_update_hint()
	line_started.emit(speaker, text)


func _finish_line() -> void:
	_typing = false
	text_label.visible_characters = -1
	_update_hint()
	line_completed.emit(speaker, text_label.text)


func _update_hint() -> void:
	var key := InputHints.key_for(advance_action)
	var cancel := InputHints.key_for(&"ui_cancel")
	if _typing:
		hint_label.text = "[%s] Skip" % key
	elif not _queue.is_empty():
		hint_label.text = "[%s] Next" % key
	elif _source is NPC:
		hint_label.text = "[%s] Talk   [%s] Close" % [key, cancel]
	else:
		hint_label.text = "[%s] Close" % key


func _source_still_focused() -> bool:
	return _source is NPC and detector != null and detector.focused != null \
			and detector.focused == (_source as NPC).interactable


func _on_npc_spoke(npc_name: String, line: String, npc: NPC) -> void:
	if hide_world_bubbles:
		npc.speech_label.visible = false
	show_line(npc_name, line, npc.body_color, npc)


func _on_focus_changed(_interactable: Interactable) -> void:
	# Walking away from whoever is speaking ends the conversation.
	if is_open() and _source is NPC and not _source_still_focused():
		close()


func _on_node_added(node: Node) -> void:
	if node is NPC:
		bind_npc(node)


func _bind_existing_npcs() -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is NPC:
			bind_npc(node)
		stack.append_array(node.get_children())
