class_name InputPromptIcons
extends RefCounted
## Pixel-art key and mouse icons for input prompts, looked up from the actual InputMap
## bindings. Icons are cropped from assets/ui/input_prompts/input_prompts.png by
## tools/crop_input_prompts.py (32 px tall; show them 1:1 or at an integer scale with
## nearest filtering). Keys the sheet has no icon for (I, O, P, T, U, Y, 0, 7-9, numpad,
## punctuation...) return null; InputPrompt draws a plain keycap with the key name instead.

const ICON_DIR := "res://assets/ui/input_prompts/icons/"
## Keys whose icon name is not "key_" + the lower-case key name.
const SPECIAL_KEYS := {
	KEY_ESCAPE: "key_esc", KEY_SHIFT: "key_shift", KEY_CTRL: "key_ctrl", KEY_ALT: "key_alt",
	KEY_TAB: "key_tab", KEY_SPACE: "key_space", KEY_ENTER: "key_enter", KEY_KP_ENTER: "key_enter",
	KEY_BACKSPACE: "key_backspace", KEY_DELETE: "key_delete", KEY_INSERT: "key_insert",
	KEY_HOME: "key_home", KEY_END: "key_end", KEY_PAGEUP: "key_page_up", KEY_PAGEDOWN: "key_page_down",
	KEY_UP: "key_up", KEY_DOWN: "key_down", KEY_LEFT: "key_left", KEY_RIGHT: "key_right",
}
const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: "mouse_left", MOUSE_BUTTON_RIGHT: "mouse_right", MOUSE_BUTTON_MIDDLE: "mouse_middle",
	MOUSE_BUTTON_WHEEL_UP: "mouse_wheel", MOUSE_BUTTON_WHEEL_DOWN: "mouse_wheel",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}

static var _cache: Dictionary[String, Texture2D] = {}


## The binding to show for action: its first event that has an icon (zoom_in shows the
## mouse wheel rather than "="), else its first keyboard event, else its first mouse
## button, else its first event (null when unbound or unknown).
static func primary_event(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	for event in events:
		if texture_for_event(event) != null:
			return event
	for event in events:
		if event is InputEventKey:
			return event
	for event in events:
		if event is InputEventMouseButton:
			return event
	return events[0] if not events.is_empty() else null


## Key as labelled on the player's keyboard layout. Bindings use physical keys, so on
## AZERTY the move_forward binding (physical W) is shown as Z.
static func display_keycode(event: InputEventKey) -> Key:
	if event.physical_keycode == KEY_NONE:
		return event.keycode
	# The headless display server (tests, CI) has no keyboard layout to ask.
	if DisplayServer.get_name() == "headless":
		return event.physical_keycode
	var mapped := DisplayServer.keyboard_get_keycode_from_physical(event.physical_keycode)
	return mapped if mapped != KEY_NONE else event.physical_keycode


static func texture_for_action(action: StringName) -> Texture2D:
	return texture_for_event(primary_event(action))


static func texture_for_event(event: InputEvent) -> Texture2D:
	if event is InputEventKey:
		return texture_for_key(display_keycode(event))
	if event is InputEventMouseButton:
		return _load(MOUSE_BUTTONS.get((event as InputEventMouseButton).button_index, ""))
	return null


static func texture_for_key(key: Key) -> Texture2D:
	if key == KEY_NONE:
		return null
	var icon_name: String = SPECIAL_KEYS.get(key, "key_" + OS.get_keycode_string(key).to_lower())
	return _load(icon_name)


## Icon for a key name as printed in hint text ("E", "Escape", "Space", "F3"), or null.
static func texture_for_key_name(key_name: String) -> Texture2D:
	return texture_for_key(OS.find_keycode_from_string(key_name))


## Short text for a binding, used on fallback keycaps ("E", "Escape", "Wheel Up", "?").
static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		return OS.get_keycode_string(display_keycode(event))
	if event is InputEventMouseButton:
		return MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "Mouse")
	return "?"


static func has_icon_name(icon_name: String) -> bool:
	return _load(icon_name) != null


static func _load(icon_name: String) -> Texture2D:
	if icon_name.is_empty():
		return null
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := ICON_DIR + icon_name + ".png"
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[icon_name] = texture
	return texture
