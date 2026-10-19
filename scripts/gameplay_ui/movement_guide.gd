class_name MovementGuide
extends PanelContainer
## HUD keyboard guide: the courier's controls as animated pixel-art keycaps, no text. The
## four movement keys sit in the usual inverted T (forward on top; left, back, right below);
## a second block shows the other controls (interact, shield, map, journal, equipment on top;
## run/dash and attack below). Each keycap presses down while its key is held
## (AnimatedKeycap), so W + D show together.
##
## Keys are read from the InputMap (InputPromptIcons.primary_event), so rebinding shows the
## new key; a key without an icon gets a drawn keycap. The guide rebuilds itself when a
## binding changes. GameplayHUD places it and hides it when the
## UISettings.SHOW_MOVEMENT_GUIDE preference is off.

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const FORWARD := &"move_forward"
const LEFT := &"move_left"
const BACK := &"move_back"
const RIGHT := &"move_right"
const ACTIONS: Array[StringName] = [FORWARD, LEFT, BACK, RIGHT]
## The other controls, as two rows (top, bottom). Actions without a binding are skipped.
const CONTROL_ROWS: Array = [
	[&"interact", &"package_shield", &"toggle_map", &"toggle_journal", &"toggle_equipment"],
	[&"run", &"combat_magic_bolt"],
]
const KEY_GAP := 4
## Seconds between binding checks.
const BINDING_CHECK_INTERVAL := 0.5

## Action -> keycap face (the icon TextureRect, or a drawn fallback) currently shown.
var keycaps: Dictionary[StringName, Control] = {}
## Action -> the AnimatedKeycap holding that face (every key in the guide).
var animated: Dictionary[StringName, AnimatedKeycap] = {}
var _keys: HBoxContainer
var _binding_signature := ""
var _check_left: float = 0.0


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	var compact := StyleBoxFlat.new()
	compact.bg_color = Color(0.07, 0.06, 0.12, 0.55)
	compact.set_corner_radius_all(8)
	compact.set_content_margin_all(8)
	add_theme_stylebox_override(&"panel", compact)
	_keys = HBoxContainer.new()
	_keys.add_theme_constant_override(&"separation", 14)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keys)
	refresh()


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = BINDING_CHECK_INTERVAL
	if binding_signature() != _binding_signature:
		refresh()


## Rebuilds the keycaps from the current bindings.
func refresh() -> void:
	_binding_signature = binding_signature()
	for child in _keys.get_children():
		_keys.remove_child(child)
		child.queue_free()
	keycaps.clear()
	animated.clear()
	_keys.add_child(_block([[FORWARD], [LEFT, BACK, RIGHT]], BoxContainer.ALIGNMENT_CENTER))
	var rows: Array = []
	for row: Array in CONTROL_ROWS:
		rows.append(row.filter(func(action: StringName) -> bool: return InputPromptIcons.primary_event(action) != null))
	_keys.add_child(_block(rows, BoxContainer.ALIGNMENT_BEGIN))


## Every shown action's key, e.g. "W|A|S|D|E|..." (changes when a binding changes).
static func binding_signature() -> String:
	var parts: PackedStringArray = []
	var all: Array[StringName] = ACTIONS.duplicate()
	for row: Array in CONTROL_ROWS:
		for action: StringName in row:
			all.append(action)
	for action in all:
		var event := InputPromptIcons.primary_event(action)
		parts.append(InputPromptIcons.event_text(event) if event != null else "?")
	return "|".join(parts)


func _block(rows: Array, alignment: BoxContainer.AlignmentMode) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", KEY_GAP - AnimatedKeycap.PRESS_DEPTH + 2)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.size_flags_vertical = Control.SIZE_SHRINK_END
	for actions: Array in rows:
		var row := HBoxContainer.new()
		row.alignment = alignment
		row.add_theme_constant_override(&"separation", KEY_GAP)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for action: StringName in actions:
			var keycap := AnimatedKeycap.create(action)
			keycaps[action] = keycap.face
			animated[action] = keycap
			row.add_child(keycap)
		block.add_child(row)
	return block
