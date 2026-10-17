class_name InteractionPrompt
extends CanvasLayer
## Shows "[E] Talk to X" while the player's InteractionDetector has a focus.

@export var detector: InteractionDetector
@export var action: StringName = &"interact"

@onready var panel: Control = %PromptPanel
@onready var label: Label = %PromptLabel


func _ready() -> void:
	panel.visible = false
	if detector != null:
		detector.focus_changed.connect(_on_focus_changed)


func _on_focus_changed(interactable: Interactable) -> void:
	if interactable == null:
		panel.visible = false
		return
	label.text = "[%s] %s" % [_action_key_text(), interactable.get_prompt_text()]
	panel.visible = true


func _action_key_text() -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
			return OS.get_keycode_string(keycode)
	return "?"
