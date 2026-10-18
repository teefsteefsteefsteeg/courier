class_name InteractionPrompt
extends CanvasLayer
## Shows "[E] Talk to X" while the player's InteractionDetector has a focus.
## Other UI (e.g. the dialogue box) can suppress it while it owns the screen. It also
## hides while any modal window (group "ui_modal": journal, quest board) is open; the
## open quest journal additionally hides the whole layer.

## Text color for context prompts (e.g. "Deliver ... to ...").
const CONTEXT_COLOR := Color(1.0, 0.86, 0.4)

@export var detector: InteractionDetector
@export var action: StringName = &"interact"

@onready var panel: Control = %PromptPanel
@onready var label: Label = %PromptLabel

var _focused: Interactable = null
var _suppressed: bool = false
var _modal_open: bool = false


func _ready() -> void:
	panel.visible = false
	add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	if detector != null:
		detector.focus_changed.connect(_on_focus_changed)


func _process(_delta: float) -> void:
	var width := minf(520.0, get_viewport().get_visible_rect().size.x * 0.4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	(panel.get_parent() as Control).offset_top = -144.0
	if not _sync_modal() and _focused != null and is_instance_valid(_focused) and get_prompt_text() != label.text:
		# Context prompts change without a focus change (package picked up, quest advanced).
		_refresh()


func _physics_process(_delta: float) -> void:
	# Also checked on physics ticks: several can run before the next idle frame, and a
	# modal opened in between must not leave the prompt on screen for them.
	_sync_modal()


## Groups have no change signal, and modals come from both World/UI and gameplay.
## Returns true when the modal state changed (and the prompt was refreshed).
func _sync_modal() -> bool:
	var modal_open := get_tree().get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0
	if modal_open == _modal_open:
		return false
	_modal_open = modal_open
	_refresh()
	return true


## Full prompt line for the current focus, e.g. "[E] Deliver Ordinary Parcel to Merchant Mira".
func get_prompt_text() -> String:
	if _focused == null or not is_instance_valid(_focused):
		return ""
	return "[%s] %s" % [InputHints.key_for(action), _focused.get_prompt_text_for(_interactor())]


## True when the focused object shows a context prompt instead of its default one.
func is_context_prompt() -> bool:
	return _focused != null and is_instance_valid(_focused) \
			and _focused.get_prompt_text_for(_interactor()) != _focused.get_prompt_text()


func _interactor() -> Node:
	return detector.get_parent() if detector != null else null


func set_suppressed(suppressed: bool) -> void:
	_suppressed = suppressed
	_refresh()


func _on_focus_changed(interactable: Interactable) -> void:
	_focused = interactable
	_refresh()


func _refresh() -> void:
	if _focused == null or not is_instance_valid(_focused):
		panel.visible = false
		return
	label.text = get_prompt_text()
	if is_context_prompt():
		label.add_theme_color_override(&"font_color", CONTEXT_COLOR)
	else:
		label.remove_theme_color_override(&"font_color")
	panel.visible = not _suppressed and not _modal_open
