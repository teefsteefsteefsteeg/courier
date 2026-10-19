class_name AnimatedKeycap
extends Control
## A pixel-art keycap for one InputMap action that physically presses down: released it
## stands raised on a dark shadow; pressed, the face drops PRESS_DEPTH pixels, the shadow
## shrinks and the face darkens. It stays down while the key is held and springs back on
## release. A short tap stays visible for MIN_TAP seconds, so it is never missed between
## frames and never left stuck.
##
## The key comes from the action's InputMap binding (InputPromptIcons). Pressed state is the
## action or the physical key, so it also shows while a modal window has the courier
## paused. It only reads input and never consumes events.

const PRESS_DEPTH := 3
const SHADOW_COLOR := Color(0.03, 0.02, 0.07, 0.85)
const PRESSED_TINT := Color(0.74, 0.72, 0.8)
## A tap shorter than this is still shown pressed for this long (seconds).
const MIN_TAP := 0.09

var action: StringName
## The keycap face (a TextureRect icon, or a drawn fallback keycap).
var face: Control
var pressed := false
var _event: InputEvent
var _tap_left := 0.0
var _offset := 0.0


static func create(for_action: StringName, scale: int = 1) -> AnimatedKeycap:
	var keycap := AnimatedKeycap.new()
	keycap.action = for_action
	keycap.name = String(for_action)
	keycap._event = InputPromptIcons.primary_event(for_action)
	keycap.face = InputPrompt.make_keycap_for_event(keycap._event, scale)
	keycap.face.name = "Face"
	keycap.add_child(keycap.face)
	return keycap


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_fit()


func _fit() -> void:
	var face_size := face.get_combined_minimum_size()
	custom_minimum_size = face_size + Vector2(0, PRESS_DEPTH)
	face.size = face_size
	face.position = Vector2.ZERO


## True while the bound key is down (or the action is pressed by any means).
func is_key_down() -> bool:
	if action != &"" and InputMap.has_action(action) and Input.is_action_pressed(action):
		return true
	var key := _event as InputEventKey
	return key != null and Input.is_physical_key_pressed(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if action != &"" and InputMap.has_action(action) and event.is_action_pressed(action):
		_tap_left = MIN_TAP
	elif _event is InputEventKey and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == (_event as InputEventKey).physical_keycode:
		_tap_left = MIN_TAP


func _process(delta: float) -> void:
	_tap_left = maxf(_tap_left - delta, 0.0)
	var down := is_key_down() or _tap_left > 0.0
	if down != pressed:
		pressed = down
	# Press snaps down; release springs back in about 60 ms.
	var target := float(PRESS_DEPTH) if pressed else 0.0
	_offset = target if pressed else move_toward(_offset, target, delta * PRESS_DEPTH / 0.06)
	face.position.y = roundf(_offset)
	face.modulate = PRESSED_TINT if pressed else Color.WHITE
	queue_redraw()


func _draw() -> void:
	# The shadow under the face: PRESS_DEPTH px deep when raised, 1 px when pressed.
	var face_size := face.size
	var depth := maxf(float(PRESS_DEPTH) - roundf(_offset), 1.0)
	draw_rect(Rect2(Vector2(2, face.position.y + face_size.y - 2), Vector2(face_size.x - 4, depth + 2)), SHADOW_COLOR)
