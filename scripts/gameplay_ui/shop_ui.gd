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
	for item in catalog.items:
		if item != null:
			item_list.add_child(_build_row(item))
	_refresh_rows()


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
	var kind := item.get_attack_summary() if item.is_weapon() else ItemDefinition.slot_name(item.slot)
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


func _focus_first_button() -> void:
	for item_id in rows:
		var button: Button = rows[item_id]["button"]
		if not button.disabled:
			button.grab_focus.call_deferred()
			return
	close_button.grab_focus.call_deferred()
