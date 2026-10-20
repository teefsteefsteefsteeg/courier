class_name InputPrompt
extends HBoxContainer
## Reusable input prompt: the pixel-art keycap of each action's actual InputMap binding,
## followed by optional text, e.g. [E] Talk, or [W][A][S][D] Move.
##
## Icons come from InputPromptIcons and are drawn with nearest filtering at an integer
## scale. A binding without an icon gets a plain drawn keycap with the key name, so a
## prompt never shows the wrong key. Call refresh() after rebinding an action.
##
## Other HUD widgets join AVOID_GROUP so world-anchored prompts can stay clear of them.

## Controls (tracker, wallet, minimap, dialogue box...) that world-anchored prompts avoid.
const AVOID_GROUP := &"input_prompt_avoid"
const KEYCAP_BG := Color(0.24, 0.23, 0.34)
const KEYCAP_BORDER := Color(0.05, 0.05, 0.1)
const KEYCAP_TEXT := Color(0.93, 0.93, 0.96)

## One keycap per action, in order.
@export var actions: Array[StringName] = []:
	set(value):
		actions = value
		_queue_refresh()
@export var text: String = "":
	set(value):
		text = value
		_queue_refresh()
@export_range(1, 4) var icon_scale: int = 1:
	set(value):
		icon_scale = value
		_queue_refresh()
@export var font_size: int = 18:
	set(value):
		font_size = value
		_queue_refresh()

## The text label (null when text is empty).
var text_label: Label = null
## One keycap Control per action (TextureRect for an icon, PanelContainer for a fallback).
var keycaps: Array[Control] = []
var _refresh_queued: bool = false


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 6)


func _ready() -> void:
	refresh()


func set_action(action: StringName) -> void:
	actions = [action]


## True when every action has a pixel-art icon (no fallback keycaps).
func has_all_icons() -> bool:
	return not keycaps.is_empty() and keycaps.all(func(c: Control) -> bool: return c is TextureRect)


## Rebuilds the keycaps from the current InputMap and the text label.
func refresh() -> void:
	_refresh_queued = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	keycaps.clear()
	text_label = null
	for action in actions:
		var keycap := make_keycap_for_event(InputPromptIcons.primary_event(action), icon_scale, font_size)
		keycap.set_meta(&"action", action)
		keycaps.append(keycap)
		add_child(keycap)
	if not text.is_empty():
		text_label = Label.new()
		text_label.text = text
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text_label.add_theme_font_size_override(&"font_size", font_size)
		text_label.add_theme_color_override(&"font_outline_color", Color(0.03, 0.04, 0.06))
		text_label.add_theme_constant_override(&"outline_size", 6)
		add_child(text_label)


## Keycap for a binding: its icon, or a drawn keycap with the key name when the
## sheet has none (or "?" when unbound).
static func make_keycap_for_event(event: InputEvent, scale: int = 1, fallback_font_size: int = 16) -> Control:
	var texture := InputPromptIcons.texture_for_event(event)
	if texture != null:
		return make_icon(texture, scale)
	return make_fallback_keycap(InputPromptIcons.event_text(event) if event != null else "?", scale, fallback_font_size)


static func make_icon(texture: Texture2D, scale: int = 1) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.custom_minimum_size = texture.get_size() * scale
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Keycap faces for keys whose names are words (OS.get_keycode_string).
const GLYPHS := {"Equal": "=", "Minus": "-", "Comma": ",", "Period": ".", "Slash": "/", "Semicolon": ";",
		"Apostrophe": "'", "BracketLeft": "[", "BracketRight": "]", "Backslash": "\\", "QuoteLeft": "`"}


## A keycap drawn in the sheet's colours, for keys the sheet has no icon for.
static func make_fallback_keycap(key_text: String, scale: int = 1, fallback_font_size: int = 16) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = KEYCAP_BG
	style.border_color = KEYCAP_BORDER
	style.set_border_width_all(2 * scale)
	style.border_width_bottom = 4 * scale
	style.set_corner_radius_all(3 * scale)
	style.content_margin_left = 7 * scale
	style.content_margin_right = 7 * scale
	style.content_margin_top = 2 * scale
	style.content_margin_bottom = 3 * scale
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = Vector2(32, 32) * scale
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	# Punctuation keys show their symbol ("=" rather than "Equal").
	label.text = GLYPHS.get(key_text, key_text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", mini(fallback_font_size, 16) * scale)
	label.add_theme_color_override(&"font_color", KEYCAP_TEXT)
	panel.add_child(label)
	return panel


func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	refresh.call_deferred()
