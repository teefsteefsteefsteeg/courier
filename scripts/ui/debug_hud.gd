class_name DebugHUD
extends CanvasLayer
## Developer overlay: FPS, player position, speed, movement state, focused interactable.
## Toggle with the `toggle_debug_hud` action (F3).

@export var player: PlayerController
@export var camera_rig: IsoCameraRig

@onready var label: Label = %DebugLabel


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var p := player.global_position
	var focused := player.interaction.focused
	var text := "FPS: %d\n" % Engine.get_frames_per_second()
	text += "Pos: (%.2f, %.2f, %.2f)\n" % [p.x, p.y, p.z]
	text += "Speed: %.2f m/s\n" % player.get_horizontal_speed()
	text += "State: %s\n" % player.movement.get_state_name()
	text += "On floor: %s\n" % player.is_on_floor()
	text += "Focus: %s" % (focused.display_name if focused != null else "-")
	if camera_rig != null:
		text += "\nZoom: %.1f m" % camera_rig.camera.size
	label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug_hud"):
		visible = not visible
		get_viewport().set_input_as_handled()
