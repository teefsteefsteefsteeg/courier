class_name MovementGuide
extends PanelContainer
## HUD movement key guide: the four movement bindings as pixel-art keycaps in the usual
## inverted-T (forward on top; left, back, right below) with a "Move" label.
##
## Keys are read from the InputMap (InputPromptIcons.primary_event), so rebinding to the
## arrow keys shows the arrows; a key without an icon gets a drawn keycap. The guide
## rebuilds itself when a binding changes. GameplayHUD places it and hides it when the
## UISettings.SHOW_MOVEMENT_GUIDE preference is off.

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const FORWARD := &"move_forward"
const LEFT := &"move_left"
const BACK := &"move_back"
const RIGHT := &"move_right"
const ACTIONS: Array[StringName] = [FORWARD, LEFT, BACK, RIGHT]
const KEY_GAP := 4
## Seconds between binding checks.
const BINDING_CHECK_INTERVAL := 0.5

@export var label_text: String = "Move"

## Action -> keycap Control currently shown (read by tests).
var keycaps: Dictionary[StringName, Control] = {}
var label: Label
var _keys: VBoxContainer
var _binding_signature := ""
var _check_left: float = 0.0


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_keys = VBoxContainer.new()
	_keys.add_theme_constant_override(&"separation", KEY_GAP)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_keys)
	label = Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(0.92, 0.9, 0.98))
	row.add_child(label)
	refresh()


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = BINDING_CHECK_INTERVAL
	if binding_signature() != _binding_signature:
		refresh()


## Rebuilds the keycaps from the current movement bindings.
func refresh() -> void:
	_binding_signature = binding_signature()
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	keycaps.clear()
	var top := _row([FORWARD])
	var bottom := _row([LEFT, BACK, RIGHT])
	_keys.add_child(top)
	_keys.add_child(bottom)


## Text of the four bindings, e.g. "W|A|S|D" (changes when a binding changes).
static func binding_signature() -> String:
	var parts: PackedStringArray = []
	for action in ACTIONS:
		var event := InputPromptIcons.primary_event(action)
		parts.append(InputPromptIcons.event_text(event) if event != null else "?")
	return "|".join(parts)


func _row(actions: Array[StringName]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", KEY_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action in actions:
		var keycap := InputPrompt.make_keycap_for_event(InputPromptIcons.primary_event(action))
		keycap.name = String(action)
		keycaps[action] = keycap
		row.add_child(keycap)
	return row
