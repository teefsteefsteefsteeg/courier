class_name InputHints
extends RefCounted
## Turns Input Map actions into short key labels for on-screen hints ("E", "J", "Escape").


static func key_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
			return OS.get_keycode_string(keycode)
	return "?"
