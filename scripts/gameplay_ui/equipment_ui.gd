class_name EquipmentUI
extends CanvasLayer
## Inventory window (toggle_equipment, Q since Phase 8). Phase 7 redesign: a slate frame and parchment
## page (Humble Pixel inventory pack, assets/ui/inventory/) with two views, switched with
## the side tabs or [Q] (quick_switch_tool; the courier's tool switch cannot fire while the window
## is open, so the key is free here):
##   Weapons & Gear  weapons, then armor (off-hand and body armor), as a grid of item cells
##   Tools & Goods   tools, then seeds, produce and gathered materials with their counts
##   Provisions      (Phase 8) health potions, mana potions, food and combat buffs with their
##                   counts; selecting one shows its effects, a Use button and the
##                   consumable quick slots (keys 6-0). The header shows how many kinds of
##                   provisions the pack holds (CourierInventory.CONSUMABLE_BAG_SLOTS).
## Each cell shows the item's icon, name, enhancement badge (+1..+5 in the level's colour),
## an E for equipped and its quick-slot number. Selecting a cell shows its details on the
## right: stats, enhancement stars, status and the actions (Equip / Unequip, quick slots
## 1-5). Unowned items are dimmed and have their actions disabled. Selecting a seed makes
## it the one garden beds plant first (FarmService.preferred_seed).
## Everything goes through CourierInventory (the one inventory); EquipmentStats does the rest.
##
## Modal like ShopUI: joins "ui_modal", pauses the courier's input, closes on Escape / Tab /
## the Close button, and refuses to open over another window or a dialogue line.

signal opened
signal closed
signal view_changed(view: int)

enum View { WEAPONS, TOOLS, PROVISIONS }

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const UI := "res://assets/ui/inventory/"
const GOLD := Color(1, 0.84, 0.3)
const INK := Color(0.30, 0.19, 0.11)
const INK_SOFT := Color(0.45, 0.33, 0.22)
const VIEW_TITLES := ["Weapons & Gear", "Tools & Goods", "Provisions"]
const VIEW_COUNT := 3
const CELL_SIZE := Vector2(104, 112)

@export var inventory: CourierInventory

var root_control: Control
var panel: PanelContainer
## The section list of the current view (headers and grids).
var item_list: VBoxContainer
var feedback_label: Label
var close_button: Button
## "Show enhancement effects" (UISettings.SHOW_ENHANCEMENT_VFX) in the footer.
var vfx_toggle: CheckButton
var title_label: Label
var switch_hint: Label
var gold_label: Label
var tab_buttons: Array[Button] = []
var view: int = View.WEAPONS
## item_id -> {"row" (grid cell), "status", "equip", "slots": Array[Button], "item",
## "badge", "actions"} (read by tests).
var rows: Dictionary[StringName, Dictionary] = {}
## material_id -> {"cell", "label", "material"}: carried materials (read by tests).
var material_rows: Dictionary[StringName, Dictionary] = {}
var selected_id: StringName = &""
## material_id -> {"cell", "label", "item": ConsumableItem} (read by tests).
var consumable_rows: Dictionary[StringName, Dictionary] = {}
## The consumable shown in the details panel (Provisions view).
var selected_consumable: StringName = &""
var bag_label: Label
var _consumable_actions: VBoxContainer
var _use_button: Button
var _consumable_slot_buttons: Array[Button] = []
var _views: Array[VBoxContainer] = []
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_kind: Label
var _detail_stats: Label
var _detail_stars: Label
var _detail_actions: Control
var _player: PlayerController = null
var _slot_assigned_style: StyleBoxFlat
var _cell_styles: Dictionary = {}


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
		inventory.enhancement_changed.connect(func(_i, _l): _refresh())
		inventory.consumable_slots_changed.connect(_refresh)


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
	vfx_toggle.set_pressed_no_signal(UISettings.show_enhancement_vfx())
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


## Shows the Weapons & Gear, Tools & Goods or Provisions view.
func set_view(value: int) -> void:
	view = value
	for index in _views.size():
		_views[index].visible = index == view
	item_list = _views[view]
	for index in tab_buttons.size():
		tab_buttons[index].set_pressed_no_signal(index == view)
		tab_buttons[index].add_theme_stylebox_override(&"normal", _cell_styles["tab_on"] if index == view else _cell_styles["tab_off"])
	title_label.text = VIEW_TITLES[view]
	switch_hint.text = "[%s] %s" % [InputHints.key_for(&"quick_switch_tool"), VIEW_TITLES[(view + 1) % VIEW_COUNT]]
	# Keep the selection in the view on screen.
	if view == View.PROVISIONS:
		if not consumable_rows.has(selected_consumable):
			_select_first()
	else:
		var selected: Dictionary = rows.get(selected_id, {})
		if selected.is_empty() or _view_of(selected["item"]) != view:
			_select_first()
	_refresh()
	view_changed.emit(view)


## [Q]: Weapons & Gear -> Tools & Goods -> Provisions -> Weapons & Gear.
func toggle_view() -> void:
	set_view((view + 1) % VIEW_COUNT)


## Opening and closing run in _input: the inventory key is Tab (Phase 8 revision), and a
## focused button would otherwise take Tab for focus navigation; opening consumes the key
## only when the window actually opens. [Q] (quick_switch_tool) switches the view while
## the window is open, before the tool/weapon switch could see it.
func _input(event: InputEvent) -> void:
	if not is_open():
		if event.is_action_pressed(&"toggle_equipment"):
			open()
			if is_open():
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_equipment") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"quick_switch_tool"):
		toggle_view()
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


## Shows item_id's details (switching to its view).
func select_item(item_id: StringName) -> void:
	var row: Dictionary = rows.get(item_id, {})
	if row.is_empty():
		return
	selected_id = item_id
	if _view_of(row["item"]) != view:
		set_view(_view_of(row["item"]))
	_refresh()


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


## Shows a consumable's details (switching to Provisions).
func select_consumable(material_id: StringName) -> void:
	if not consumable_rows.has(material_id):
		return
	selected_consumable = material_id
	if view != View.PROVISIONS:
		set_view(View.PROVISIONS)
	_refresh()


## Uses one of a consumable as the Use button does. Returns whether it was used.
func use_consumable(material_id: StringName) -> bool:
	var vitals := CourierVitals.find(get_tree())
	var item := inventory.get_material_definition(material_id) as ConsumableItem
	if vitals == null or item == null:
		return false
	var used := vitals.consume(material_id)
	feedback_label.text = ("Used %s: %s." % [item.display_name, ", ".join(item.get_effect_lines())]) if used else "Can't use %s now." % item.display_name
	_refresh()
	return used


func _on_consumable_slot_pressed(index: int) -> void:
	var item := inventory.get_material_definition(selected_consumable) as ConsumableItem
	if item == null:
		return
	if inventory.find_consumable_slot(item.material_id) == index:
		inventory.clear_consumable_slot(index)
		feedback_label.text = "Cleared provisions slot [%s]." % InputHints.key_for(CourierVitals.SLOT_ACTIONS[index])
	elif inventory.assign_consumable_slot(index, item.material_id):
		feedback_label.text = "%s is on provisions slot [%s]." % [item.display_name, InputHints.key_for(CourierVitals.SLOT_ACTIONS[index])]
	_refresh()


func _on_material_pressed(material: MaterialItem) -> void:
	var farm := FarmService.find(get_tree())
	if material.kind == MaterialItem.Kind.SEED and farm != null:
		farm.set_preferred_seed(material.material_id)
		feedback_label.text = "Garden beds will plant %s first." % material.display_name
	else:
		feedback_label.text = material.description
	_refresh()


func _view_of(item: ItemDefinition) -> int:
	return View.TOOLS if item.is_tool() else View.WEAPONS


# --- layout ---------------------------------------------------------------------

func _texture_style(file: String, margin: int, content: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(UI + file)
	style.set_texture_margin_all(margin)
	style.set_content_margin_all(content)
	return style


func _flat(bg: Color, border: Color, width: int = 2, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(6)
	return style


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _build() -> void:
	_slot_assigned_style = StyleBoxFlat.new()
	_slot_assigned_style.bg_color = GOLD
	_slot_assigned_style.border_color = Color(1, 0.95, 0.7)
	_slot_assigned_style.set_border_width_all(2)
	_slot_assigned_style.set_corner_radius_all(4)
	_cell_styles = {
		"cell": _flat(Color(0.93, 0.85, 0.68), Color(0.62, 0.47, 0.30)),
		"cell_hover": _flat(Color(0.97, 0.9, 0.74), Color(0.80, 0.58, 0.28)),
		"cell_selected": _flat(Color(1.0, 0.93, 0.72), Color(0.85, 0.55, 0.12), 3),
		"tab_on": _texture_style("tab_on.png", 0, 12.0),
		"tab_off": _texture_style("tab_off.png", 0, 12.0),
	}
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
	# The pack's frame is only a border: slate underneath, the frame drawn over it.
	var slate := _flat(Color(0.21, 0.31, 0.36), Color(0.21, 0.31, 0.36), 0, 10)
	slate.set_content_margin_all(0)
	panel.add_theme_stylebox_override(&"panel", slate)
	root_control.add_child(panel)
	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.add_theme_stylebox_override(&"panel", _texture_style("frame.png", 24, 26.0))
	panel.add_child(frame)
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override(&"separation", 10)
	frame.add_child(outer)
	# Side tabs, as on the pack's handheld.
	var tabs := VBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override(&"separation", 10)
	outer.add_child(tabs)
	for index in VIEW_COUNT:
		var tab := Button.new()
		tab.name = ["WeaponsTab", "ToolsTab", "ProvisionsTab"][index]
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(72, 72)
		tab.icon = [load("res://assets/ui/item_icons/iron_sword.png"), load(UI + "icon_tools.png"), load("res://assets/ui/item_icons/health_potion.png")][index]
		tab.expand_icon = true
		tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.tooltip_text = VIEW_TITLES[index]
		for state in [&"hover", &"pressed", &"hover_pressed", &"focus"]:
			tab.add_theme_stylebox_override(state, _cell_styles["tab_on"])
		tab.pressed.connect(set_view.bind(index))
		tabs.add_child(tab)
		tab_buttons.append(tab)
	var tab_hint := _label("[%s]" % InputHints.key_for(&"quick_switch_tool"), 16, Color(0.85, 0.82, 0.95))
	tab_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tabs.add_child(tab_hint)
	InputPromptLabel.attach(tab_hint)
	var page := PanelContainer.new()
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_stylebox_override(&"panel", _texture_style("parchment.png", 14, 20.0))
	outer.add_child(page)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	page.add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	body.add_child(header)
	title_label = _label("", 30, INK)
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	switch_hint = _label("", 18, INK_SOFT)
	switch_hint.name = "SwitchHint"
	header.add_child(switch_hint)
	InputPromptLabel.attach(switch_hint)
	bag_label = _label("", 16, INK_SOFT)
	bag_label.name = "Pack"
	bag_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(bag_label)
	gold_label = _label("", 20, Color(0.62, 0.42, 0.06))
	header.add_child(gold_label)
	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.47, 0.30, 0.6)
	rule.custom_minimum_size.y = 2
	body.add_child(rule)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 16)
	body.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var views := VBoxContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(views)
	for index in VIEW_COUNT:
		var list := VBoxContainer.new()
		list.name = ["WeaponsView", "ToolsView", "ProvisionsView"][index]
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override(&"separation", 6)
		views.add_child(list)
		_views.append(list)
	item_list = _views[0]
	content.add_child(_build_detail())
	feedback_label = _label("", 17, Color(0.18, 0.45, 0.16))
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(feedback_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 16)
	body.add_child(footer)
	var close_hint := _label("[%s] Switch view   [%s] Close" % [InputHints.key_for(&"quick_switch_tool"), InputHints.key_for(&"toggle_equipment")], 16, INK_SOFT)
	close_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(close_hint)
	InputPromptLabel.attach(close_hint)
	# Cosmetic only: the enhancement bonuses stay when the effects are hidden.
	vfx_toggle = CheckButton.new()
	vfx_toggle.name = "EnhancementVfxToggle"
	vfx_toggle.text = "Show enhancement effects"
	vfx_toggle.tooltip_text = "Glow and aura of enhanced weapons and armor. Hiding them keeps the bonuses."
	vfx_toggle.add_theme_color_override(&"font_color", INK)
	vfx_toggle.add_theme_color_override(&"font_hover_color", INK)
	vfx_toggle.add_theme_color_override(&"font_pressed_color", INK)
	vfx_toggle.add_theme_color_override(&"font_hover_pressed_color", INK)
	vfx_toggle.add_theme_color_override(&"font_focus_color", INK)
	vfx_toggle.toggled.connect(func(on: bool) -> void: UISettings.set_value(UISettings.SHOW_ENHANCEMENT_VFX, on))
	footer.add_child(vfx_toggle)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	footer.add_child(close_button)


func _build_detail() -> Control:
	var detail := PanelContainer.new()
	detail.name = "Detail"
	detail.custom_minimum_size.x = 300
	detail.add_theme_stylebox_override(&"panel", _flat(Color(0.95, 0.88, 0.72, 0.85), Color(0.62, 0.47, 0.30), 2, 8))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	detail.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	box.add_child(top)
	_detail_icon = TextureRect.new()
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.custom_minimum_size = Vector2(80, 80)
	top.add_child(_detail_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	_detail_name = _label("", 22, INK)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_detail_name)
	_detail_kind = _label("", 15, INK_SOFT)
	_detail_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_detail_kind)
	_detail_stars = _label("", 20, GOLD)
	_detail_stars.name = "Enhancement"
	box.add_child(_detail_stars)
	_detail_stats = _label("", 16, INK)
	_detail_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_stats)
	_detail_actions = VBoxContainer.new()
	_detail_actions.name = "Actions"
	box.add_child(_detail_actions)
	# Provisions: one set of actions for whichever consumable is selected.
	_consumable_actions = VBoxContainer.new()
	_consumable_actions.name = "ConsumableActions"
	_consumable_actions.add_theme_constant_override(&"separation", 6)
	_consumable_actions.visible = false
	box.add_child(_consumable_actions)
	_use_button = Button.new()
	_use_button.name = "Use"
	_use_button.text = "Use"
	_use_button.pressed.connect(func() -> void: use_consumable(selected_consumable))
	_consumable_actions.add_child(_use_button)
	_consumable_actions.add_child(_label("Provisions slot", 14, INK_SOFT))
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override(&"separation", 4)
	_consumable_actions.add_child(slot_row)
	for index in CourierInventory.CONSUMABLE_SLOT_COUNT:
		var slot_button := Button.new()
		slot_button.text = InputHints.key_for(CourierVitals.SLOT_ACTIONS[index])
		slot_button.toggle_mode = true
		slot_button.custom_minimum_size = Vector2(44, 34)
		slot_button.pressed.connect(_on_consumable_slot_pressed.bind(index))
		for state in [&"pressed", &"hover_pressed"]:
			slot_button.add_theme_stylebox_override(state, _slot_assigned_style)
		slot_button.add_theme_color_override(&"font_pressed_color", Color(0.12, 0.08, 0.02))
		slot_button.add_theme_color_override(&"font_hover_pressed_color", Color(0.12, 0.08, 0.02))
		slot_row.add_child(slot_button)
		_consumable_slot_buttons.append(slot_button)
	return detail


func _process(_delta: float) -> void:
	if not is_open():
		return
	var view_size := root_control.get_viewport_rect().size
	var size := Vector2(minf(1100.0, view_size.x - 48.0), minf(720.0, view_size.y - 48.0))
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5


func _rebuild() -> void:
	for list in _views:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	for child in _detail_actions.get_children():
		_detail_actions.remove_child(child)
		child.queue_free()
	rows.clear()
	material_rows.clear()
	consumable_rows.clear()
	var all := inventory.get_all_definitions()
	var sections := [
		[View.WEAPONS, "Weapons", func(i: ItemDefinition) -> bool: return i.is_weapon()],
		[View.WEAPONS, "Armor", func(i: ItemDefinition) -> bool: return not i.is_weapon() and not i.is_tool()],
		[View.TOOLS, "Tools", func(i: ItemDefinition) -> bool: return i.is_tool()],
	]
	for section in sections:
		var items := all.filter(section[2])
		if items.is_empty():
			continue
		var list := _views[section[0]]
		list.add_child(_section_label(section[1]))
		var grid := _grid(section[1])
		list.add_child(grid)
		for item in items:
			grid.add_child(_build_cell(item))
			_detail_actions.add_child(_build_actions(item))
	var consumables := inventory.get_all_consumables()
	for group in [["Health Potions", MaterialItem.Kind.HEALTH_POTION], ["Mana Potions", MaterialItem.Kind.MANA_POTION],
			["Food", MaterialItem.Kind.FOOD], ["Combat Buffs", MaterialItem.Kind.BUFF]]:
		var members := consumables.filter(func(c: ConsumableItem) -> bool: return c.kind == group[1])
		if members.is_empty():
			continue
		_views[View.PROVISIONS].add_child(_section_label(group[0]))
		var grid := GridContainer.new()
		grid.name = String(group[0]).replace(" ", "")
		grid.columns = 3
		grid.add_theme_constant_override(&"h_separation", 14)
		grid.add_theme_constant_override(&"v_separation", 6)
		_views[View.PROVISIONS].add_child(grid)
		for item in members:
			grid.add_child(_build_consumable_cell(item))
	var materials := inventory.get_all_materials().filter(func(m: MaterialItem) -> bool: return not m.is_consumable())
	for group in [["Seeds", [MaterialItem.Kind.SEED]], ["Produce", [MaterialItem.Kind.PRODUCE]],
			["Materials", [MaterialItem.Kind.FISH, MaterialItem.Kind.WOOD, MaterialItem.Kind.STONE, MaterialItem.Kind.ORE, MaterialItem.Kind.CLAY]]]:
		var members := materials.filter(func(m: MaterialItem) -> bool: return (group[1] as Array).has(m.kind))
		if members.is_empty():
			continue
		_views[View.TOOLS].add_child(_section_label(group[0]))
		var grid := GridContainer.new()
		grid.name = group[0]
		grid.columns = 3
		grid.add_theme_constant_override(&"h_separation", 14)
		grid.add_theme_constant_override(&"v_separation", 6)
		_views[View.TOOLS].add_child(grid)
		for material in members:
			grid.add_child(_build_material_cell(material))
	if not rows.has(selected_id):
		selected_id = &""
	set_view(view)
	_refresh()


func _select_first() -> void:
	if view == View.PROVISIONS:
		selected_consumable = &""
		for material_id in consumable_rows:
			if selected_consumable == &"" or (inventory.get_material_count(material_id) > 0 and inventory.get_material_count(selected_consumable) == 0):
				selected_consumable = material_id
		return
	var equipped := inventory.get_equipped(ItemDefinition.Slot.MAIN_HAND) if inventory != null else null
	if equipped != null and _view_of(equipped) == view and rows.has(equipped.item_id):
		selected_id = equipped.item_id
		return
	var first_owned: StringName = &""
	var first: StringName = &""
	for item_id in rows:
		if _view_of(rows[item_id]["item"]) != view:
			continue
		if first == &"":
			first = item_id
		if first_owned == &"" and inventory.has_item(item_id):
			first_owned = item_id
	selected_id = first_owned if first_owned != &"" else first


func _section_label(text: String) -> Label:
	var label := _label(text, 20, Color(0.55, 0.22, 0.14))
	label.name = text.replace("-", "") + "Header"
	return label


func _grid(section: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = section + "Grid"
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	return grid


func _build_cell(item: ItemDefinition) -> Control:
	var cell := Button.new()
	cell.name = String(item.item_id)
	cell.custom_minimum_size = CELL_SIZE
	cell.tooltip_text = item.display_name
	cell.add_theme_stylebox_override(&"normal", _cell_styles["cell"])
	cell.add_theme_stylebox_override(&"hover", _cell_styles["cell_hover"])
	cell.add_theme_stylebox_override(&"pressed", _cell_styles["cell_selected"])
	cell.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	cell.pressed.connect(select_item.bind(item.item_id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 8
	box.offset_bottom = -6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(box)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(56, 56)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var name_label := _label(item.display_name, 13, INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var badge := _label("", 16, GOLD)
	badge.name = "Badge"
	badge.add_theme_color_override(&"font_outline_color", Color(0.12, 0.08, 0.04))
	badge.add_theme_constant_override(&"outline_size", 5)
	badge.position = Vector2(CELL_SIZE.x - 34, 4)
	cell.add_child(badge)
	var marker := _label("", 14, Color(0.15, 0.4, 0.12))
	marker.name = "Marker"
	marker.position = Vector2(8, 4)
	cell.add_child(marker)
	rows[item.item_id] = {"row": cell, "item": item, "badge": badge, "marker": marker}
	return cell


## The selected item's details panel actions, one container per item (only the selected
## one is visible).
func _build_actions(item: ItemDefinition) -> Control:
	var actions := VBoxContainer.new()
	actions.name = String(item.item_id)
	actions.add_theme_constant_override(&"separation", 6)
	var status := _label("", 16, INK_SOFT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(status)
	var equip := Button.new()
	equip.pressed.connect(_on_equip_pressed.bind(item))
	actions.add_child(equip)
	var slots: Array[Button] = []
	if item.is_quick_slottable():
		var slot_label := _label("Quick slot", 14, INK_SOFT)
		actions.add_child(slot_label)
		var slot_row := HBoxContainer.new()
		slot_row.add_theme_constant_override(&"separation", 4)
		actions.add_child(slot_row)
		for index in CourierInventory.QUICK_SLOT_COUNT:
			var slot_button := Button.new()
			slot_button.text = InputHints.key_for(StringName("quick_slot_%d" % (index + 1)))
			slot_button.toggle_mode = true
			slot_button.custom_minimum_size = Vector2(44, 34)
			slot_button.pressed.connect(_on_slot_pressed.bind(item, index))
			# The item's current slot: gold, like the equipped slot on the HUD bar.
			for state in [&"pressed", &"hover_pressed"]:
				slot_button.add_theme_stylebox_override(state, _slot_assigned_style)
			slot_button.add_theme_color_override(&"font_pressed_color", Color(0.12, 0.08, 0.02))
			slot_button.add_theme_color_override(&"font_hover_pressed_color", Color(0.12, 0.08, 0.02))
			slot_row.add_child(slot_button)
			slots.append(slot_button)
	else:
		actions.add_child(_label("Off-hand and armor have no quick slot", 14, INK_SOFT))
	var row := rows[item.item_id]
	row["status"] = status
	row["equip"] = equip
	row["slots"] = slots
	row["actions"] = actions
	return actions


func _build_material_cell(material: MaterialItem) -> Control:
	var cell := Button.new()
	cell.name = String(material.material_id)
	cell.tooltip_text = material.description
	cell.custom_minimum_size = Vector2(180, 44)
	cell.add_theme_stylebox_override(&"normal", _cell_styles["cell"])
	cell.add_theme_stylebox_override(&"hover", _cell_styles["cell_hover"])
	cell.add_theme_stylebox_override(&"pressed", _cell_styles["cell_selected"])
	cell.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	cell.pressed.connect(_on_material_pressed.bind(material))
	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 6
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 6)
	cell.add_child(line)
	var icon := TextureRect.new()
	icon.texture = material.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var label := _label("", 15, INK)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	material_rows[material.material_id] = {"cell": cell, "label": label, "material": material}
	return cell


## A carried-count cell for a food or potion; selecting it shows its details.
func _build_consumable_cell(item: ConsumableItem) -> Control:
	var cell := _build_material_cell(item)
	material_rows.erase(item.material_id)
	var button := cell as Button
	for connection in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])
	button.pressed.connect(select_consumable.bind(item.material_id))
	button.tooltip_text = "%s\n%s" % [", ".join(item.get_effect_lines()), item.description]
	var label := (cell.get_child(0) as Control).get_child(1) as Label
	# The provisions slot key, as a badge in the corner.
	var key := _label("", 13, Color(0.15, 0.4, 0.12))
	key.name = "SlotKey"
	key.add_theme_color_override(&"font_outline_color", Color(0.97, 0.92, 0.78))
	key.add_theme_constant_override(&"outline_size", 4)
	key.position = Vector2(162, -6)
	cell.add_child(key)
	consumable_rows[item.material_id] = {"cell": cell, "label": label, "item": item, "key": key}
	return cell


func _refresh() -> void:
	if inventory == null:
		return
	var wallet := CourierWallet.find(get_tree())
	gold_label.text = "%d g" % wallet.gold if wallet != null else ""
	bag_label.text = "Pack %d / %d kinds" % [inventory.get_consumable_stack_count(), CourierInventory.CONSUMABLE_BAG_SLOTS] if view == View.PROVISIONS else ""
	for material_id in consumable_rows:
		var entry := consumable_rows[material_id]
		var item: ConsumableItem = entry["item"]
		var count := inventory.get_material_count(material_id)
		var slot := inventory.find_consumable_slot(material_id)
		(entry["label"] as Label).text = "%s × %d" % [item.display_name, count]
		(entry["key"] as Label).text = InputHints.key_for(CourierVitals.SLOT_ACTIONS[slot]) if slot >= 0 else ""
		var cell := entry["cell"] as Button
		cell.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.45)
		cell.add_theme_stylebox_override(&"normal", _cell_styles["cell_selected"] if material_id == selected_consumable else _cell_styles["cell"])
	for item_id in rows:
		var row := rows[item_id]
		if not row.has("status"):
			continue
		var item: ItemDefinition = row["item"]
		var status: Label = row["status"]
		var equip: Button = row["equip"]
		var owned := inventory.has_item(item_id)
		var equipped := inventory.is_equipped(item_id)
		var slot := inventory.find_quick_slot(item_id)
		var level := inventory.get_enhancement(item_id)
		var cell := row["row"] as Button
		cell.modulate = Color.WHITE if owned else Color(1, 1, 1, 0.45)
		cell.add_theme_stylebox_override(&"normal", _cell_styles["cell_selected"] if item_id == selected_id else _cell_styles["cell"])
		var badge := row["badge"] as Label
		badge.text = Enhancement.level_text(level)
		badge.add_theme_color_override(&"font_color", Enhancement.level_color(level))
		(row["marker"] as Label).text = ("E" if equipped else "") + (" %d" % (slot + 1) if slot >= 0 else "")
		if equipped:
			status.text = "Equipped" + (" · quick slot %d" % (slot + 1) if slot >= 0 else "")
			status.add_theme_color_override(&"font_color", Color(0.62, 0.42, 0.06))
		elif owned:
			status.text = "Owned" + (" · quick slot %d" % (slot + 1) if slot >= 0 else "")
			status.add_theme_color_override(&"font_color", Color(0.18, 0.45, 0.16))
		else:
			status.text = "Not owned · buy it from the Toolwright" if item.is_tool() else "Not owned · buy it at the Armory"
			status.add_theme_color_override(&"font_color", INK_SOFT)
		equip.text = "Unequip" if equipped else "Equip"
		equip.disabled = not owned
		var slot_buttons: Array = row["slots"]
		for index in slot_buttons.size():
			var button := slot_buttons[index] as Button
			button.disabled = not owned
			button.set_pressed_no_signal(slot == index)
		(row["actions"] as Control).visible = item_id == selected_id
	_refresh_detail()
	var farm := FarmService.find(get_tree())
	for material_id in material_rows:
		var cell := material_rows[material_id]
		var material: MaterialItem = cell["material"]
		var count := inventory.get_material_count(material_id)
		var text := "%s × %d" % [material.display_name, count]
		if material.kind == MaterialItem.Kind.SEED and farm != null and farm.preferred_seed == material_id:
			text += "  ★"
		(cell["label"] as Label).text = text
		(cell["cell"] as Control).modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.45)


func _refresh_detail() -> void:
	_consumable_actions.visible = view == View.PROVISIONS and consumable_rows.has(selected_consumable)
	_detail_actions.visible = view != View.PROVISIONS
	if view == View.PROVISIONS:
		_refresh_consumable_detail()
		return
	var row: Dictionary = rows.get(selected_id, {})
	if row.is_empty():
		_detail_icon.texture = null
		_detail_name.text = "Nothing here yet"
		_detail_kind.text = ""
		_detail_stats.text = ""
		_detail_stars.text = ""
		return
	var item: ItemDefinition = row["item"]
	var level := inventory.get_enhancement(item.item_id)
	_detail_icon.texture = item.icon
	_detail_name.text = item.display_name + (" " + Enhancement.level_text(level) if level > 0 else "")
	var summary := item.get_attack_summary() if item.is_weapon() or item.is_tool() else ItemDefinition.slot_name(item.slot)
	if item.two_handed:
		summary += " · two-handed"
	_detail_kind.text = summary
	_detail_stats.text = "\n".join(item.get_stat_lines()) + ("\n\n" + item.description if not item.description.is_empty() else "")
	if item.is_tool():
		_detail_stars.text = ""
	else:
		_detail_stars.text = "Enhancement  " + "★".repeat(level) + "☆".repeat(Enhancement.MAX_LEVEL - level) + ("  " + Enhancement.TIER_NAMES[level] if level > 0 else "")
		_detail_stars.add_theme_color_override(&"font_color", Enhancement.level_color(level).darkened(0.25) if level > 0 else INK_SOFT)


func _refresh_consumable_detail() -> void:
	var entry: Dictionary = consumable_rows.get(selected_consumable, {})
	_detail_stars.text = ""
	if entry.is_empty():
		_detail_icon.texture = null
		_detail_name.text = "No provisions yet"
		_detail_kind.text = ""
		_detail_stats.text = "Buy food and potions from Grocer Tilda at the Food Market."
		return
	var item: ConsumableItem = entry["item"]
	var count := inventory.get_material_count(item.material_id)
	_detail_icon.texture = item.icon
	_detail_name.text = item.display_name
	_detail_kind.text = "%s · carried %d / %d" % [MaterialItem.kind_name(item.kind), count, item.get_stack_limit()]
	_detail_stats.text = "\n".join(item.get_effect_lines()) + "\n\n" + item.description
	_use_button.disabled = count <= 0
	_use_button.text = "Use (%d left)" % count if count > 0 else "None left"
	var slot := inventory.find_consumable_slot(item.material_id)
	for index in _consumable_slot_buttons.size():
		_consumable_slot_buttons[index].set_pressed_no_signal(slot == index)
