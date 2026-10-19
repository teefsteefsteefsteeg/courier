class_name QuickConsumableBar
extends PanelContainer
## HUD row with the five consumable quick slots (Phase 8; CourierInventory consumable slots,
## keys consumable_slot_1..5 = 6 7 8 9 0). Each slot shows the food or potion's icon, its
## key and how many are carried; an empty stack is dimmed. A key press (CourierVitals) or a
## click uses one. The potion cooldown is drawn as a dark sweep over potions.

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const SLOT_SIZE := Vector2(46, 46)

@export var inventory: CourierInventory

## One Button per slot (read by tests).
var slot_buttons: Array[Button] = []
var _counts: Array[Label] = []
var _cooldowns: Array[ColorRect] = []
var _style_full: StyleBoxFlat
var _style_empty: StyleBoxFlat


func _ready() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_bind.call_deferred()


func _bind() -> void:
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if inventory != null:
		inventory.consumable_slots_changed.connect(refresh)
		inventory.materials_changed.connect(func(_m, _c, _d): refresh())
	refresh()


## Uses the consumable in slot index (0-based), as its key would.
func use(index: int) -> bool:
	var vitals := CourierVitals.find(get_tree())
	return vitals != null and vitals.use_slot(index)


func refresh() -> void:
	if inventory == null:
		return
	for index in slot_buttons.size():
		var item := inventory.get_consumable_slot(index)
		var button := slot_buttons[index]
		var count := inventory.get_material_count(item.material_id) if item != null else 0
		var key := InputHints.key_for(CourierVitals.SLOT_ACTIONS[index])
		button.icon = item.icon if item != null else null
		button.text = "" if item != null else "-"
		button.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.45)
		for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			button.add_theme_stylebox_override(state, _style_full if count > 0 else _style_empty)
		_counts[index].text = str(count) if item != null else ""
		button.tooltip_text = ("%s ×%d [%s]\n%s" % [item.display_name, count, key, ", ".join(item.get_effect_lines())]) if item != null else "Empty provisions slot [%s]: put food or a potion here in the inventory [%s]" % [key, InputHints.key_for(&"toggle_equipment")]


func _process(_delta: float) -> void:
	var vitals := CourierVitals.find(get_tree())
	if vitals == null or inventory == null:
		return
	var ratio := vitals.potion_cooldown_left / CourierVitals.POTION_COOLDOWN
	for index in _cooldowns.size():
		var item := inventory.get_consumable_slot(index)
		var shade := _cooldowns[index]
		shade.visible = item != null and item.is_potion() and ratio > 0.0
		if shade.visible:
			shade.size = Vector2(SLOT_SIZE.x, SLOT_SIZE.y * ratio)


func _build() -> void:
	_style_full = _slot_style(Color(0.1, 0.12, 0.08, 0.9), Color(0.55, 0.7, 0.42), 1)
	_style_empty = _slot_style(Color(0.05, 0.05, 0.08, 0.6), Color(0.3, 0.3, 0.36), 1)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 2)
	add_child(body)
	var title := Label.new()
	title.name = "Title"
	title.text = "Provisions"
	title.add_theme_font_size_override(&"font_size", 13)
	title.add_theme_color_override(&"font_color", Color(0.7, 0.9, 0.6))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)
	var row := HBoxContainer.new()
	row.name = "Slots"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 5)
	body.add_child(row)
	for index in CourierInventory.CONSUMABLE_SLOT_COUNT:
		var button := Button.new()
		button.name = "Slot%d" % (index + 1)
		button.custom_minimum_size = SLOT_SIZE
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_constant_override(&"icon_max_width", 32)
		button.add_theme_font_size_override(&"font_size", 20)
		button.pressed.connect(use.bind(index))
		row.add_child(button)
		slot_buttons.append(button)
		var shade := ColorRect.new()
		shade.name = "Cooldown"
		shade.color = Color(0, 0, 0, 0.55)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.visible = false
		button.add_child(shade)
		_cooldowns.append(shade)
		var key_icon := TextureRect.new()
		key_icon.name = "Key"
		key_icon.texture = InputPromptIcons.texture_for_action(CourierVitals.SLOT_ACTIONS[index])
		key_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		key_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		key_icon.size = Vector2(20, 20)
		key_icon.position = Vector2(-4, -6)
		key_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(key_icon)
		var count := Label.new()
		count.name = "Count"
		count.add_theme_font_size_override(&"font_size", 13)
		count.add_theme_color_override(&"font_color", Color(1, 1, 0.9))
		count.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
		count.add_theme_constant_override(&"outline_size", 4)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.position = Vector2(4, SLOT_SIZE.y - 20)
		count.size = Vector2(SLOT_SIZE.x - 6, 18)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(count)
		_counts.append(count)


static func _slot_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	return style
