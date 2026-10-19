class_name ShopUI
extends CanvasLayer
## Shop window for any Merchant (group "merchants"): one row per catalog item with its
## pixel-art icon, name, slot, stats, description and price, and one button that reads
## Buy (disabled with the reason when the courier cannot afford it), Equip or Unequip.
## Purchases go through ShopService (CourierWallet + CourierInventory); equipping goes
## through CourierInventory, and EquipmentStats updates the courier's combat stats.
##
## Modal like QuestBoardUI: joins "ui_modal", pauses the courier's input, closes on
## Escape / interact / the Close button, refuses to open over another window, and closes
## any open dialogue line.
##
## When the catalog buys_materials (the Toolwright), a "Sell your goods" section lists every
## material the courier carries with its price and a Sell all button (gold in, materials out).

signal opened(merchant: Merchant)
signal purchased(item: ItemDefinition)
signal closed

const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const ICON_SCALE := 2
## Catalog sold by the Armory location's weaponsmith.
const ARMORY_CATALOG := "res://data/shops/armory.tres"

@export var wallet: CourierWallet
@export var inventory: CourierInventory

var root_control: Control
var panel: PanelContainer
var title_label: Label
var greeting_label: Label
var gold_label: Label
var item_list: VBoxContainer
var feedback_label: Label
var close_hint: Label
var close_button: Button
## item_id -> {"row", "button", "price", "status"} for the shown catalog (read by tests).
var rows: Dictionary[StringName, Dictionary] = {}
## material_id -> {"row", "button", "count", "material"} in the Sell section (read by tests).
var sell_rows: Dictionary[StringName, Dictionary] = {}
## material_id -> {"row", "buy_one", "buy_five", "count", "material"} for goods the merchant
## sells by the unit (Phase 7 seeds; read by tests).
var goods_rows: Dictionary[StringName, Dictionary] = {}
## item_id -> {"row", "button", "label", "item"} in the Enhance section of a merchant that
## enhances gear (Phase 7, Brenna; read by tests).
var enhance_rows: Dictionary[StringName, Dictionary] = {}
var _sell_header: Control = null
var merchant: Merchant = null
var _player: PlayerController = null


func _ready() -> void:
	layer = 20
	_build()
	root_control.visible = false
	_connect.call_deferred()


func _connect() -> void:
	if wallet == null:
		wallet = CourierWallet.find(get_tree())
	if inventory == null:
		inventory = CourierInventory.find(get_tree())
	if wallet != null:
		wallet.gold_changed.connect(func(_v, _d): _refresh_rows())
	if inventory != null:
		inventory.item_added.connect(func(_i): _refresh_rows())
		inventory.equipment_changed.connect(func(_s, _i): _refresh_rows())
		inventory.materials_changed.connect(func(_m, _c, _d): _refresh_rows())
	for node in get_tree().get_nodes_in_group(Merchant.GROUP):
		bind_merchant(node as Merchant)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is Merchant:
			bind_merchant.call_deferred(node))
	_attach_armory_merchants()


## The building/visual Armory location (scripts/world/armory.gd) has a shopkeeper NPC
## (`merchant`) but no shop logic. Give that NPC a Merchant selling ARMORY_CATALOG at
## runtime, so talking to the weaponsmith opens this window. (Embedding merchant.gd in the
## NPC scene instead made Godot report leaked scripts and resources at exit.)
func _attach_armory_merchants() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for armory in scene.find_children("*", "Armory", true, false):
		var shopkeeper := armory.get(&"merchant") as NPC
		if shopkeeper == null or shopkeeper.get_node_or_null(^"ShopMerchant") != null:
			continue
		var shop_merchant := Merchant.new()
		shop_merchant.name = "ShopMerchant"
		shop_merchant.catalog = load(ARMORY_CATALOG) as ShopCatalog
		shopkeeper.add_child(shop_merchant)
	# Other shop locations (the Toolwright's stall) name their own shopkeeper and catalog.
	for location in get_tree().get_nodes_in_group(ToolStall.GROUP):
		var keeper := location.get(&"merchant") as NPC
		var catalog := location.get(&"catalog") as ShopCatalog
		if keeper == null or catalog == null or keeper.get_node_or_null(^"ShopMerchant") != null:
			continue
		var stall_merchant := Merchant.new()
		stall_merchant.name = "ShopMerchant"
		stall_merchant.catalog = catalog
		keeper.add_child(stall_merchant)


## Listens to a merchant (merchants added later are bound automatically).
func bind_merchant(target: Merchant) -> void:
	if target != null and not target.shop_requested.is_connected(open):
		target.shop_requested.connect(open)


func is_open() -> bool:
	return root_control.visible


func open(target: Merchant, interactor: Node = null) -> void:
	if is_open() or target == null or target.get_catalog() == null or wallet == null or inventory == null:
		return
	if get_tree().get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0:
		return
	merchant = target
	for node in get_tree().get_nodes_in_group(DialogueBox.OPEN_GROUP):
		(node as DialogueBox).close()
	_player = interactor as PlayerController
	if _player == null:
		_player = get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	if _player != null:
		_player.input_enabled = false
	var catalog := target.get_catalog()
	title_label.text = target.get_merchant_name() if target.get_merchant_name() != catalog.title else catalog.title
	greeting_label.text = catalog.greeting
	greeting_label.visible = not catalog.greeting.is_empty()
	feedback_label.text = ""
	_rebuild(catalog)
	root_control.visible = true
	add_to_group(QuestJournal.MODAL_GROUP)
	_focus_first_button()
	opened.emit(target)


func close() -> void:
	if not is_open():
		return
	root_control.visible = false
	remove_from_group(QuestJournal.MODAL_GROUP)
	merchant = null
	if _player != null:
		# Deferred so the key press that closed the shop cannot act on the courier this frame.
		_player.set_deferred(&"input_enabled", true)
		_player = null
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact"):
		close()
		get_viewport().set_input_as_handled()


## Presses an item's button (Buy, Equip or Unequip) as the player would.
func activate(item_id: StringName) -> void:
	var row: Dictionary = rows.get(item_id, {})
	if not row.is_empty() and not (row["button"] as Button).disabled:
		(row["button"] as Button).pressed.emit()


func _on_item_pressed(item: ItemDefinition) -> void:
	if not inventory.has_item(item.item_id):
		var result := ShopService.buy(wallet, inventory, item)
		feedback_label.text = ShopService.result_text(result, item, wallet)
		if result == ShopService.PurchaseResult.OK:
			feedback_label.text += "  Equip it to use it."
			purchased.emit(item)
	elif inventory.is_equipped(item.item_id):
		inventory.unequip(item.slot)
		feedback_label.text = "Unequipped %s." % item.display_name
	else:
		inventory.equip(item.item_id)
		feedback_label.text = "Equipped %s." % item.display_name
	_refresh_rows()


# --- layout ---------------------------------------------------------------------

func _build() -> void:
	root_control = Control.new()
	root_control.name = "ShopRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.theme = THEME
	add_child(root_control)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(dim)

	panel = PanelContainer.new()
	panel.name = "ShopPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	root_control.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	panel.add_child(body)

	var header := HBoxContainer.new()
	body.add_child(header)
	title_label = Label.new()
	title_label.add_theme_font_size_override(&"font_size", 28)
	title_label.add_theme_color_override(&"font_color", Color(1, 0.84, 0.3))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	gold_label = Label.new()
	gold_label.add_theme_font_size_override(&"font_size", 22)
	gold_label.add_theme_color_override(&"font_color", Color(1, 0.84, 0.3))
	header.add_child(gold_label)
	greeting_label = Label.new()
	greeting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greeting_label.add_theme_color_override(&"font_color", Color(0.85, 0.82, 0.95))
	body.add_child(greeting_label)

	var scroll := ScrollContainer.new()
	scroll.name = "Items"
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
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override(&"separation", 16)
	body.add_child(footer)
	close_hint = Label.new()
	close_hint.text = "[%s] Close" % InputHints.key_for(&"ui_cancel")
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
	var size := Vector2(minf(860.0, view.x - 64.0), minf(720.0, view.y - 64.0))
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5


func _rebuild(catalog: ShopCatalog) -> void:
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	rows.clear()
	sell_rows.clear()
	goods_rows.clear()
	enhance_rows.clear()
	_sell_header = null
	for item in catalog.items:
		if item != null:
			item_list.add_child(_build_row(item))
	if catalog.enhances_items:
		var enhance_header := Label.new()
		enhance_header.name = "EnhanceHeader"
		enhance_header.theme_type_variation = &"ContractTitle"
		enhance_header.text = "Enhance your gear (+1 to +5): gold and iron ore"
		item_list.add_child(enhance_header)
		for item in inventory.get_all_definitions():
			if Enhancement.can_enhance(item):
				item_list.add_child(_build_enhance_row(item))
	if not catalog.sells_materials.is_empty():
		var goods_header := Label.new()
		goods_header.name = "GoodsHeader"
		goods_header.theme_type_variation = &"ContractTitle"
		var provisions := catalog.sells_materials.any(func(m: MaterialItem) -> bool: return m != null and m.is_consumable())
		goods_header.text = "Food, potions and provisions" if provisions else "Seeds for the Courier's Garden"
		item_list.add_child(goods_header)
		for material in catalog.sells_materials:
			if material != null and material.buy_price > 0:
				item_list.add_child(_build_goods_row(material))
	if catalog.buys_materials:
		var header := Label.new()
		header.name = "SellHeader"
		header.theme_type_variation = &"ContractTitle"
		header.text = "Sell your goods"
		item_list.add_child(header)
		_sell_header = header
		# Gathered goods only: provisions are bought, not sold back.
		for material in inventory.get_all_materials():
			if material.sell_price > 0 and not material.is_consumable():
				item_list.add_child(_build_sell_row(material))
	_refresh_rows()


## Enhances an owned item one level here. Returns the result.
func enhance_item(item_id: StringName) -> ShopService.EnhanceResult:
	if not is_open() or merchant == null:
		return ShopService.EnhanceResult.NO_SERVICES
	var item := inventory.get_definition(item_id)
	var level := inventory.get_enhancement(item_id)
	var result := ShopService.enhance(wallet, inventory, merchant.get_catalog(), item_id)
	feedback_label.text = ShopService.enhance_text(result, item, inventory.get_enhancement(item_id) if result == ShopService.EnhanceResult.OK else level)
	_refresh_rows()
	return result


func _build_enhance_row(item: ItemDefinition) -> Control:
	var row := PanelContainer.new()
	row.name = "Enhance_" + String(item.item_id)
	row.theme_type_variation = &"ContractPanel"
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.custom_minimum_size = Vector2(32, 32) * ICON_SCALE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var label := Label.new()
	label.theme_type_variation = &"ContractTitle"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	var button := Button.new()
	button.custom_minimum_size.x = 170
	button.pressed.connect(func() -> void: enhance_item(item.item_id))
	line.add_child(button)
	enhance_rows[item.item_id] = {"row": row, "button": button, "label": label, "item": item}
	return row


## Buys amount of a material this merchant sells. Returns the gold spent.
func buy_goods(material_id: StringName, amount: int) -> int:
	if not is_open() or inventory == null or wallet == null or merchant == null or not goods_rows.has(material_id):
		return 0
	var material: MaterialItem = goods_rows[material_id]["material"]
	var spent := ShopService.buy_material(wallet, inventory, merchant.get_catalog(), material, amount)
	if spent > 0:
		feedback_label.text = "Bought %d %s for %d gold." % [amount, material.display_name, spent]
	elif inventory.get_room_for(material) < amount:
		feedback_label.text = _no_room_text(material)
	else:
		feedback_label.text = "Not enough gold: %d %s cost %d." % [amount, material.display_name, material.buy_price * amount]
	_refresh_rows()
	return spent


func _build_goods_row(material: MaterialItem) -> Control:
	var row := PanelContainer.new()
	row.name = "Goods_" + String(material.material_id)
	row.theme_type_variation = &"ContractPanel"
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = material.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.custom_minimum_size = Vector2(32, 32) * ICON_SCALE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"ContractTitle"
	var kind_text := MaterialItem.kind_name(material.kind)
	name_label.text = "%s · %s · %d g each" % [material.display_name, kind_text, material.buy_price] if material.is_consumable() and kind_text != material.display_name else "%s · %d g each" % [material.display_name, material.buy_price]
	text.add_child(name_label)
	if material is ConsumableItem:
		var effects := Label.new()
		effects.name = "Effects"
		effects.theme_type_variation = &"ContractDetail"
		effects.add_theme_color_override(&"font_color", Color(0.2, 0.5, 0.18))
		effects.text = ", ".join((material as ConsumableItem).get_effect_lines())
		text.add_child(effects)
	row.tooltip_text = material.description
	var count := Label.new()
	count.theme_type_variation = &"ContractDetail"
	count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(count)
	var side := HBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override(&"separation", 6)
	line.add_child(side)
	var buy_one := Button.new()
	buy_one.text = "Buy 1"
	buy_one.pressed.connect(func() -> void: buy_goods(material.material_id, 1))
	side.add_child(buy_one)
	var buy_five := Button.new()
	buy_five.text = "Buy 5"
	buy_five.pressed.connect(func() -> void: buy_goods(material.material_id, 5))
	side.add_child(buy_five)
	goods_rows[material.material_id] = {"row": row, "buy_one": buy_one, "buy_five": buy_five, "count": count, "material": material}
	return row


func _no_room_text(material: MaterialItem) -> String:
	if inventory.get_material_count(material.material_id) == 0 and material.is_consumable():
		return "Your pack is full: %d kinds of provisions at most. Use or sell some first." % CourierInventory.CONSUMABLE_BAG_SLOTS
	return "No room: you can carry %d %s at most." % [material.get_stack_limit(), material.display_name]


## Sells every carried unit of material. Returns the gold earned.
func sell_all(material_id: StringName) -> int:
	if not is_open() or inventory == null or wallet == null or merchant == null:
		return 0
	var material := inventory.get_material_definition(material_id)
	var count := inventory.get_material_count(material_id)
	var earned := ShopService.sell_material(wallet, inventory, merchant.get_catalog(), material_id, count)
	if earned <= 0:
		return 0
	feedback_label.text = "Sold %d %s for %d gold." % [count, material.display_name, earned]
	_refresh_rows()
	return earned


func _build_sell_row(material: MaterialItem) -> Control:
	var row := PanelContainer.new()
	row.name = "Sell_" + String(material.material_id)
	row.theme_type_variation = &"ContractPanel"
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.texture = material.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.custom_minimum_size = Vector2(32, 32) * ICON_SCALE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"ContractTitle"
	name_label.text = material.display_name
	text.add_child(name_label)
	var count := Label.new()
	count.theme_type_variation = &"ContractDetail"
	text.add_child(count)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.custom_minimum_size.x = 170
	line.add_child(side)
	var price := Label.new()
	price.theme_type_variation = &"ContractTitle"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.text = "%d g each" % material.sell_price
	side.add_child(price)
	var button := Button.new()
	button.pressed.connect(func() -> void: sell_all(material.material_id))
	side.add_child(button)
	sell_rows[material.material_id] = {"row": row, "button": button, "count": count, "material": material}
	return row


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
	text.add_theme_constant_override(&"separation", 2)
	line.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"ContractTitle"
	name_label.text = item.display_name
	text.add_child(name_label)
	var stats := Label.new()
	stats.theme_type_variation = &"ContractDetail"
	var stat_lines := item.get_stat_lines()
	var kind := item.get_attack_summary() if item.is_weapon() or item.is_tool() else ItemDefinition.slot_name(item.slot)
	if item.two_handed:
		kind += " · two-handed"
	stats.text = "%s  ·  %s" % [kind, ", ".join(stat_lines) if not stat_lines.is_empty() else "no bonuses"]
	text.add_child(stats)
	var description := Label.new()
	description.theme_type_variation = &"ContractDetail"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = item.description
	text.add_child(description)

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.custom_minimum_size.x = 170
	line.add_child(side)
	var price := Label.new()
	price.theme_type_variation = &"ContractTitle"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.text = "%d g" % item.price
	side.add_child(price)
	var status := Label.new()
	status.theme_type_variation = &"ContractDetail"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(status)
	var button := Button.new()
	button.pressed.connect(_on_item_pressed.bind(item))
	side.add_child(button)
	rows[item.item_id] = {"row": row, "button": button, "price": price, "status": status, "item": item}
	return row


## Updates gold, every row's button and status from the wallet and inventory.
func _refresh_rows() -> void:
	if wallet == null or inventory == null:
		return
	gold_label.text = "Gold: %d" % wallet.gold
	for item_id in rows:
		var row := rows[item_id]
		var item: ItemDefinition = row["item"]
		var button: Button = row["button"]
		var status: Label = row["status"]
		button.tooltip_text = ""
		if inventory.is_equipped(item_id):
			button.text = "Unequip"
			button.disabled = false
			status.text = "Equipped"
		elif inventory.has_item(item_id):
			button.text = "Equip"
			button.disabled = false
			status.text = "Owned"
		else:
			var check := ShopService.can_buy(wallet, inventory, item)
			button.text = "Buy"
			button.disabled = check != ShopService.PurchaseResult.OK
			status.text = "Need %d more gold" % (item.price - wallet.gold) if check == ShopService.PurchaseResult.NOT_ENOUGH_GOLD else ""
			if button.disabled:
				button.tooltip_text = ShopService.result_text(check, item, wallet)
	for item_id in enhance_rows:
		var enhance := enhance_rows[item_id]
		var item: ItemDefinition = enhance["item"]
		var level := inventory.get_enhancement(item_id)
		(enhance["row"] as Control).visible = inventory.has_item(item_id)
		var label := enhance["label"] as Label
		var button := enhance["button"] as Button
		if level >= Enhancement.MAX_LEVEL:
			label.text = "%s +%d · fully enhanced" % [item.display_name, level]
			button.text = "Max"
			button.disabled = true
		else:
			label.text = "%s %s → +%d · %d g, %d iron ore" % [item.display_name, Enhancement.level_text(level) if level > 0 else "+0", level + 1, Enhancement.gold_cost(level), Enhancement.ore_cost(level)]
			label.add_theme_color_override(&"font_color", Enhancement.level_color(level + 1).darkened(0.45))
			var check := ShopService.can_enhance(wallet, inventory, merchant.get_catalog() if merchant != null else null, item_id)
			button.text = "Enhance"
			button.disabled = check != ShopService.EnhanceResult.OK
			button.tooltip_text = ShopService.enhance_text(check, item, level) if button.disabled else ""
	for material_id in goods_rows:
		var goods := goods_rows[material_id]
		var material: MaterialItem = goods["material"]
		var room := inventory.get_room_for(material)
		var carried := "You carry %d / %d" % [inventory.get_material_count(material_id), material.get_stack_limit()] if material.is_consumable() else "You carry %d" % inventory.get_material_count(material_id)
		(goods["count"] as Label).text = "%s · %s" % [carried, material.description]
		for key_amount in [["buy_one", 1], ["buy_five", 5]]:
			var buy := goods[key_amount[0]] as Button
			buy.disabled = wallet.gold < material.buy_price * int(key_amount[1]) or room < int(key_amount[1])
			buy.tooltip_text = _no_room_text(material) if room < int(key_amount[1]) else ""
	# Materials: only the ones carried are shown.
	var any_to_sell := false
	for material_id in sell_rows:
		var sell := sell_rows[material_id]
		var material: MaterialItem = sell["material"]
		var count := inventory.get_material_count(material_id)
		(sell["row"] as Control).visible = count > 0
		any_to_sell = any_to_sell or count > 0
		(sell["count"] as Label).text = "You carry %d · %s" % [count, material.description]
		(sell["button"] as Button).text = "Sell all (%d g)" % (count * material.sell_price)
		(sell["button"] as Button).disabled = count <= 0
	if _sell_header != null:
		(_sell_header as Label).text = "Sell your goods" if any_to_sell else "Sell your goods: bring fish, wood, stone, ore, clay or produce"


func _focus_first_button() -> void:
	for item_id in rows:
		var button: Button = rows[item_id]["button"]
		if not button.disabled:
			button.grab_focus.call_deferred()
			return
	close_button.grab_focus.call_deferred()
