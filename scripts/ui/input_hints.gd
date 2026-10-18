class_name InputHints
extends RefCounted
## Turns Input Map actions into short key labels for on-screen hints ("E", "J", "Escape").
## Keys are named as labelled on the player's layout (see InputPromptIcons.display_keycode);
## InputPromptLabel turns "[E]" hint tokens into pixel-art keycaps.


static func key_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string(InputPromptIcons.display_keycode(event as InputEventKey))
	return "?"
