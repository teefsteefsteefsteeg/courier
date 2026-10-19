class_name EquipmentUI
extends CanvasLayer
## Equipment window (toggle_equipment, Tab): every item the courier could own, grouped as
## Weapons, Tools and Off-hand and marked Equipped, Owned or Not owned, then the carried
## Materials (Phase 5H). Owned items can be equipped or unequipped; owned weapons and tools
## can be put in any of the five quick slots (pressing an item's current slot clears it).
## Unowned items are dimmed with no actions, so they can never be equipped or slotted.
## Everything goes through CourierInventory; EquipmentStats does the rest.
##
## Modal like ShopUI: joins "ui_modal", pauses the courier's input, closes on Escape / Tab /
## the Close button, and refuses to open over another window or a dialogue line.

signal opened
signal closed

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const ICON_SCALE := 2
const GOLD := Color(1, 0.84, 0.3)

@export var inventory: CourierInventory

var root_control: Control
var panel: PanelContainer
var item_list: VBoxContainer
var feedback_label: Label
var close_button: Button
## item_id -> {"row", "status", "equip", "slots": Array[Button], "item"} (read by tests).
var rows: Dictionary[StringName, Dictionary] = {}
## material_id -> {"cell", "label", "material"}: carried materials (read by tests).
var material_rows: Dictionary[StringName, Dictionary] = {}
var _player: PlayerController = null
var _slot_assigned_style: StyleBoxFlat


func _ready() -> void:
	layer = 20
	_build()
	root_control.visible = false
	_bind.call_deferred()


func _bind() -> void:
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if inventory != null:
		inventory.item_added.connect(func(_i): _refresh())
		inventory.equipment_changed.connect(func(_s, _i): _refresh())
		inventory.quick_slots_changed.connect(_refresh)
		inventory.materials_changed.connect(func(_m, _c, _d): _refresh())


func is_open() -> bool:
	return root_control.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	if is_open() or inventory == null:
		return
	var tree := get_tree()
	if tree.get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0 or tree.get_node_count_in_group(DialogueBox.OPEN_GROUP) > 0:
		return
	_player = tree.get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	if _player != null:
		if not _player.input_enabled:
			_player = null
			return
		_player.input_enabled = false
	feedback_label.text = ""
	_rebuild()
	root_control.visible = true
	add_to_group(QuestJournal.MODAL_GROUP)
	close_button.grab_focus.call_deferred()
	opened.emit()


func close() -> void:
	if not is_open():
		return
	root_control.visible = false
	remove_from_group(QuestJournal.MODAL_GROUP)
	if _player != null:
		# Deferred so the key that closed the window cannot act on the courier this frame.
		_player.set_deferred(&"input_enabled", true)
		_player = null
	closed.emit()


## Closing runs in _input: a focused button would otherwise take Tab for focus navigation.
func _input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed(&"toggle_equipment") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() and event.is_action_pressed(&"toggle_equipment"):
		open()
		get_viewport().set_input_as_handled()


## Presses an item's Equip / Unequip button as the player would.
func activate_equip(item_id: StringName) -> void:
	var row: Dictionary = rows.get(item_id, {})
	if not row.is_empty() and not (row["equip"] as Button).disabled:
		(row["equip"] as Button).pressed.emit()


## Presses an item's quick-slot button index (0-based) as the player would.
func activate_slot(item_id: StringName, index: int) -> void:
	var row: Dictionary = rows.get(item_id, {})
	if row.is_empty() or (row["slots"] as Array).is_empty():
		return
	var button := (row["slots"] as Array)[index] as Button
	if not button.disabled:
		button.pressed.emit()


func _on_equip_pressed(item: ItemDefinition) -> void:
	if inventory.is_equipped(item.item_id):
		inventory.unequip(item.slot)
		feedback_label.text = "Unequipped %s." % item.display_name
	elif inventory.equip(item.item_id):
		feedback_label.text = "Equipped %s." % item.display_name
	else:
		feedback_label.text = "%s can't be used with a two-handed weapon." % item.display_name
	_refresh()


func _on_slot_pressed(item: ItemDefinition, index: int) -> void:
	if inventory.find_quick_slot(item.item_id) == index:
		inventory.clear_quick_slot(index)
		feedback_label.text = "Cleared quick slot %d." % (index + 1)
	elif inventory.assign_quick_slot(index, item.item_id):
		feedback_label.text = "%s is on quick slot %d [%s]." % [item.display_name, index + 1, InputHints.key_for(StringName("quick_slot_%d" % (index + 1)))]
	_refresh()


# --- layout ---------------------------------------------------------------------

func _build() -> void:
	_slot_assigned_style = StyleBoxFlat.new()
	_slot_assigned_style.bg_color = GOLD
	_slot_assigned_style.border_color = Color(1, 0.95, 0.7)
	_slot_assigned_style.set_border_width_all(2)
	_slot_assigned_style.set_corner_radius_all(4)
	root_control = Control.new()
	root_control.name = "EquipmentRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.theme = THEME
	add_child(root_control)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(dim)
	panel = PanelContainer.new()
	panel.name = "EquipmentPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	root_control.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	panel.add_child(body)
	var title := Label.new()
	title.text = "Equipment"
	title.add_theme_font_size_override(&"font_size", 28)
	title.add_theme_color_override(&"font_color", GOLD)
	body.add_child(title)
	var hint := Label.new()
	hint.text = "Equip owned gear, or put a weapon or tool on a quick slot and switch with [%s]-[%s]." % [InputHints.key_for(&"quick_slot_1"), InputHints.key_for(&"quick_slot_5")]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", Color(0.85, 0.82, 0.95))
	body.add_child(hint)
	InputPromptLabel.attach(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override(&"separation", 8)
	scroll.add_child(item_list)
	feedback_label = Label.new()
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_color_override(&"font_color", Color(0.6, 1.0, 0.6))
	body.add_child(feedback_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 16)
	body.add_child(footer)
	var close_hint := Label.new()
	close_hint.text = "[%s] Close" % InputHints.key_for(&"toggle_equipment")
	close_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(close_hint)
	InputPromptLabel.attach(close_hint)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	footer.add_child(close_button)


func _process(_delta: float) -> void:
	if not is_open():
		return
	var view := root_control.get_viewport_rect().size
	var size := Vector2(minf(900.0, view.x - 64.0), minf(720.0, view.y - 64.0))
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5


func _rebuild() -> void:
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	rows.clear()
	material_rows.clear()
	var all := inventory.get_all_definitions()
	for section in [["Weapons", func(i: ItemDefinition) -> bool: return i.is_weapon()],
			["Tools", func(i: ItemDefinition) -> bool: return i.is_tool()],
			["Off-hand", func(i: ItemDefinition) -> bool: return not i.is_weapon() and not i.is_tool()]]:
		var items := all.filter(section[1])
		if items.is_empty():
			continue
		item_list.add_child(_section_label(section[0]))
		for item in items:
			item_list.add_child(_build_row(item))
	var materials := inventory.get_all_materials()
	if not materials.is_empty():
		item_list.add_child(_section_label("Materials"))
		var grid := GridContainer.new()
		grid.name = "Materials"
		grid.columns = 4
		grid.add_theme_constant_override(&"h_separation", 18)
		grid.add_theme_constant_override(&"v_separation", 6)
		item_list.add_child(grid)
		for material in materials:
			grid.add_child(_build_material_cell(material))
	_refresh()


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.name = text.replace("-", "") + "Header"
	label.text = text
	label.add_theme_font_size_override(&"font_size", 20)
	label.add_theme_color_override(&"font_color", GOLD)
	return label


func _build_material_cell(material: MaterialItem) -> Control:
	var cell := HBoxContainer.new()
	cell.name = String(material.material_id)
	cell.add_theme_constant_override(&"separation", 6)
	cell.tooltip_text = material.description
	var icon := TextureRect.new()
	icon.texture = material.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.custom_minimum_size = Vector2(32, 32)
	cell.add_child(icon)
	var label := Label.new()
	label.theme_type_variation = &"ContractDetail"
	label.custom_minimum_size.x = 130
	# These cells sit directly on the dark panel, outside the cream item cards.
	label.add_theme_color_override(&"font_color", Color(0.96, 0.92, 0.80))
	cell.add_child(label)
	material_rows[material.material_id] = {"cell": cell, "label": label, "material": material}
	return cell


func _build_row(item: ItemDefinition) -> Control:
	var row := PanelContainer.new()
	row.name = String(item.item_id)
	row.theme_type_variation = &"ContractPanel"
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.custom_minimum_size = (item.icon.get_size() if item.icon != null else Vector2(32, 32)) * ICON_SCALE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"ContractTitle"
	name_label.text = item.display_name
	text.add_child(name_label)
	var stats := Label.new()
	stats.theme_type_variation = &"ContractDetail"
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var summary := item.get_attack_summary() if item.is_weapon() or item.is_tool() else ItemDefinition.slot_name(item.slot)
	if item.two_handed:
		summary += " · two-handed"
	stats.text = "%s  ·  %s" % [summary, ", ".join(item.get_stat_lines())]
	text.add_child(stats)
	var status := Label.new()
	status.theme_type_variation = &"ContractDetail"
	text.add_child(status)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.custom_minimum_size.x = 230
	line.add_child(side)
	var equip := Button.new()
	equip.pressed.connect(_on_equip_pressed.bind(item))
	side.add_child(equip)
	var slots: Array[Button] = []
	if item.is_quick_slottable():
		var slot_row := HBoxContainer.new()
		slot_row.add_theme_constant_override(&"separation", 4)
		side.add_child(slot_row)
		for index in CourierInventory.QUICK_SLOT_COUNT:
			var slot_button := Button.new()
			slot_button.text = InputHints.key_for(StringName("quick_slot_%d" % (index + 1)))
			slot_button.toggle_mode = true
			slot_button.custom_minimum_size = Vector2(40, 32)
			slot_button.pressed.connect(_on_slot_pressed.bind(item, index))
			# The weapon's current slot: gold, like the equipped slot on the HUD bar.
			for state in [&"pressed", &"hover_pressed"]:
				slot_button.add_theme_stylebox_override(state, _slot_assigned_style)
			slot_button.add_theme_color_override(&"font_pressed_color", Color(0.12, 0.08, 0.02))
			slot_button.add_theme_color_override(&"font_hover_pressed_color", Color(0.12, 0.08, 0.02))
			slot_row.add_child(slot_button)
			slots.append(slot_button)
	else:
		var note := Label.new()
		note.theme_type_variation = &"ContractDetail"
		note.text = "Off-hand: no quick slot"
		side.add_child(note)
	rows[item.item_id] = {"row": row, "status": status, "equip": equip, "slots": slots, "item": item}
	return row


func _refresh() -> void:
	if inventory == null:
		return
	for item_id in rows:
		var row := rows[item_id]
		var item: ItemDefinition = row["item"]
		var status: Label = row["status"]
		var equip: Button = row["equip"]
		var owned := inventory.has_item(item_id)
		var equipped := inventory.is_equipped(item_id)
		var slot := inventory.find_quick_slot(item_id)
		(row["row"] as Control).modulate = Color.WHITE if owned else Color(1, 1, 1, 0.5)
		if equipped:
			status.text = "Equipped" + (" · quick slot %d" % (slot + 1) if slot >= 0 else "")
			status.add_theme_color_override(&"font_color", GOLD)
		elif owned:
			status.text = "Owned" + (" · quick slot %d" % (slot + 1) if slot >= 0 else "")
			status.add_theme_color_override(&"font_color", Color(0.6, 1.0, 0.6))
		else:
			status.text = "Not owned · buy it from the Toolwright" if item.is_tool() else "Not owned · buy it at the Armory"
			status.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
		equip.text = "Unequip" if equipped else "Equip"
		equip.disabled = not owned
		var slot_buttons: Array = row["slots"]
		for index in slot_buttons.size():
			var button := slot_buttons[index] as Button
			button.disabled = not owned
			button.set_pressed_no_signal(slot == index)
	for material_id in material_rows:
		var cell := material_rows[material_id]
		var count := inventory.get_material_count(material_id)
		(cell["label"] as Label).text = "%s × %d" % [(cell["material"] as MaterialItem).display_name, count]
		(cell["cell"] as Control).modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.45)
