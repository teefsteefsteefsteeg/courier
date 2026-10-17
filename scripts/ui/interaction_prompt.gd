class_name InteractionPrompt
extends CanvasLayer
## Shows "[E] Talk to X" while the player's InteractionDetector has a focus.
## Other UI (e.g. the dialogue box) can suppress it while it owns the screen.

@export var detector: InteractionDetector
@export var action: StringName = &"interact"

@onready var panel: Control = %PromptPanel
@onready var label: Label = %PromptLabel

var _focused: Interactable = null
var _suppressed: bool = false


func _ready() -> void:
	panel.visible = false
	if detector != null:
		detector.focus_changed.connect(_on_focus_changed)


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
	label.text = "[%s] %s" % [InputHints.key_for(action), _focused.get_prompt_text()]
	panel.visible = not _suppressed
