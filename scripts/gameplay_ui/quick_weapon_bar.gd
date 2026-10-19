class_name QuickWeaponBar
extends PanelContainer
## HUD bar with the five quick slots (CourierInventory quick slots; weapons and, since Phase
## 5H, tools). Each slot shows its item's icon and key (quick_slot_1..5, keys 1-5 by default); the equipped weapon is
## outlined in gold and empty slots are dim. Above the slots: the weapon in hand, how it
## attacks and its stats, with WEAPON MODE / TOOL MODE beside the name (Phase 8). A key
## press or a click equips the slot's weapon, and [Q] (quick_switch_tool) swaps the last
## weapon and the last tool, except while a modal window (group ui_modal) or a dialogue
## line is open, or the courier's input is off.

## A quick slot was used; ok is false when it was empty or switching was not allowed.
signal slot_selected(index: int, ok: bool)

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const SLOT_SIZE := Vector2(52, 52)
const GOLD := Color(1, 0.84, 0.3)

@export var inventory: CourierInventory
@export var player: PlayerController

## "WEAPON MODE" / "TOOL MODE" and what [Q] switches to (Phase 8).
var mode_label: Label
var info_label: Label
var stats_label: Label
## Phase 8: the +5 weapon's ultimate and its cooldown ("[C] Flame Slash · ready");
## hidden when the weapon in hand has none.
var ultimate_label: Label
## One Button per slot (read by tests).
var slot_buttons: Array[Button] = []
var _key_icons: Array[TextureRect] = []
var _blocked := false
var _style_equipped: StyleBoxFlat
var _style_owned: StyleBoxFlat
var _style_empty: StyleBoxFlat


func _ready() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_bind.call_deferred()


func _bind() -> void:
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if player == null:
		player = get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	if inventory != null:
		inventory.quick_slots_changed.connect(refresh)
		inventory.equipment_changed.connect(func(_s, _i): refresh())
		inventory.item_added.connect(func(_i): refresh())
	refresh()


## True while weapons may be switched (no modal window, no dialogue, courier in control).
func can_switch() -> bool:
	var tree := get_tree()
	if tree.get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0 or tree.get_node_count_in_group(DialogueBox.OPEN_GROUP) > 0:
		return false
	if player != null:
		if not player.input_enabled:
			return false
		var combat := CombatController.find_on(player)
		if combat != null and combat.health != null and combat.health.is_dead():
			return false
	return true


## Equips quick slot index (0-based) as the key or a click would. Returns the result.
func select(index: int) -> bool:
	var ok := inventory != null and can_switch() and inventory.select_quick_slot(index)
	slot_selected.emit(index, ok)
	return ok


## Phase 8: [Q] swaps between the last weapon and the last tool (CourierInventory).
## Returns the item now in hand, or null when the switch was refused or impossible.
func quick_switch() -> ItemDefinition:
	if inventory == null or not can_switch():
		return null
	var item := inventory.toggle_tool_weapon()
	if item == null:
		var notices := get_tree().root.find_children("*", "QuestNotification", true, false)
		if not notices.is_empty():
			(notices[0] as QuestNotification).push_message("Nothing to switch to: own a weapon and a tool first.", QuestNotification.KIND_INFO)
	return item


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"quick_switch_tool"):
		if can_switch():
			quick_switch()
			get_viewport().set_input_as_handled()
		return
	for index in CourierInventory.QUICK_SLOT_COUNT:
		if event.is_action_pressed(StringName("quick_slot_%d" % (index + 1))):
			if can_switch():
				select(index)
				get_viewport().set_input_as_handled()
			return


func _process(_delta: float) -> void:
	_update_ultimate()
	var blocked := not can_switch()
	if blocked != _blocked:
		_blocked = blocked
		for button in slot_buttons:
			button.disabled = blocked or button.get_meta(&"empty", true)


## Redraws every slot and the weapon line from the inventory.
func refresh() -> void:
	if inventory == null:
		return
	var equipped := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND)
	for index in slot_buttons.size():
		var button := slot_buttons[index]
		var item := inventory.get_quick_slot(index)
		var key := InputHints.key_for(StringName("quick_slot_%d" % (index + 1)))
		button.set_meta(&"empty", item == null)
		button.icon = item.icon if item != null else null
		button.text = "" if item != null else "-"
		button.disabled = _blocked or item == null
		var is_equipped := item != null and item == equipped
		button.set_meta(&"equipped", is_equipped)
		var style := _style_equipped if is_equipped else (_style_owned if item != null else _style_empty)
		for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
			button.add_theme_stylebox_override(state, style)
		button.modulate = Color.WHITE if item != null else Color(1, 1, 1, 0.55)
		button.tooltip_text = ("%s [%s]" % [item.display_name, key]) if item != null else "Empty slot [%s]: assign a weapon or tool in Equipment [%s]" % [key, InputHints.key_for(&"toggle_equipment")]
	var tool_mode := equipped != null and equipped.is_tool()
	var target := inventory.get_switch_target()
	mode_label.text = "TOOL MODE" if tool_mode else "WEAPON MODE"
	# The header has no room for the key and the other item's name (the key guide shows
	# Q); the bar's tooltip names the item Q switches to.
	tooltip_text = "[%s] switches to %s" % [InputHints.key_for(&"quick_switch_tool"), target.display_name] if target != null else ""
	mode_label.add_theme_color_override(&"font_color", Color(0.55, 0.9, 0.6) if tool_mode else Color(1.0, 0.62, 0.45))
	if equipped != null and equipped.is_tool():
		info_label.text = equipped.display_name
		stats_label.text = "Tool: no attacks  ·  [%s] use" % InputHints.key_for(&"combat_magic_bolt")
	elif equipped != null and equipped.is_weapon():
		info_label.text = equipped.display_name
		stats_label.text = "%s  ·  %s" % [equipped.get_attack_summary(), ", ".join(equipped.get_stat_lines())]
	else:
		info_label.text = "Bare hands"
		stats_label.text = "Magic bolts  ·  [%s] Equipment" % InputHints.key_for(&"toggle_equipment")


func _build() -> void:
	_style_equipped = _slot_style(Color(0.16, 0.13, 0.06, 0.92), GOLD, 3)
	_style_owned = _slot_style(Color(0.08, 0.09, 0.14, 0.88), Color(0.45, 0.48, 0.6), 1)
	_style_empty = _slot_style(Color(0.05, 0.05, 0.08, 0.6), Color(0.3, 0.3, 0.36), 1)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 4)
	add_child(body)
	# Name on the left, mode on the right of the same line, so the bar keeps its height.
	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(header)
	info_label = Label.new()
	info_label.name = "WeaponName"
	info_label.add_theme_font_size_override(&"font_size", 18)
	info_label.add_theme_color_override(&"font_color", GOLD)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.clip_text = true
	header.add_child(info_label)
	mode_label = Label.new()
	mode_label.name = "Mode"
	mode_label.add_theme_font_size_override(&"font_size", 13)
	mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mode_label)
	stats_label = Label.new()
	stats_label.name = "WeaponStats"
	stats_label.add_theme_font_size_override(&"font_size", 13)
	stats_label.add_theme_color_override(&"font_color", Color(0.85, 0.85, 0.95))
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stats_label)
	InputPromptLabel.attach(stats_label)
	ultimate_label = Label.new()
	ultimate_label.name = "Ultimate"
	ultimate_label.add_theme_font_size_override(&"font_size", 13)
	ultimate_label.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.4))
	ultimate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ultimate_label.visible = false
	body.add_child(ultimate_label)
	InputPromptLabel.attach(ultimate_label)
	var row := HBoxContainer.new()
	row.name = "Slots"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 5)
	body.add_child(row)
	for index in CourierInventory.QUICK_SLOT_COUNT:
		var button := Button.new()
		button.name = "Slot%d" % (index + 1)
		button.custom_minimum_size = SLOT_SIZE
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_constant_override(&"icon_max_width", 36)
		button.add_theme_font_size_override(&"font_size", 22)
		button.pressed.connect(select.bind(index))
		row.add_child(button)
		slot_buttons.append(button)
		var key_icon := TextureRect.new()
		key_icon.name = "Key"
		key_icon.texture = InputPromptIcons.texture_for_action(StringName("quick_slot_%d" % (index + 1)))
		key_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		key_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		key_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		key_icon.custom_minimum_size = Vector2(22, 22)
		key_icon.size = Vector2(22, 22)
		key_icon.position = Vector2(-4, -6)
		key_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(key_icon)
		_key_icons.append(key_icon)


func _update_ultimate() -> void:
	if ultimate_label == null:
		return
	var ultimates := WeaponUltimates.find(get_tree())
	var skill := ultimates.current_skill() if ultimates != null else {}
	ultimate_label.visible = not skill.is_empty()
	if skill.is_empty():
		return
	var left := ultimates.get_cooldown_remaining()
	var text := "[%s] %s  ·  %s" % [InputHints.key_for(&"weapon_ultimate"), skill["name"], "ready" if left <= 0.0 else "%d s" % ceili(left)]
	if ultimate_label.text != text:
		ultimate_label.text = text


static func _slot_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	return style
