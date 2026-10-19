class_name TeleportMenu
extends CanvasLayer
## Fast-travel destination window, opened by an active TeleportPortal. Lists every portal
## in the shared location registry except the one the courier stands at: active portals
## have a Travel button; portals that are known but not activated, or not found yet, are
## shown locked and cannot be chosen. Travel goes through FastTravel.
##
## Modal like ShopUI: joins "ui_modal", pauses the courier, refuses to open over another
## window or a dialogue line, and closes on Escape / interact / the Close button.

signal opened(from_portal: TeleportPortal)
signal closed

const GROUP := &"teleport_menu"
const THEME := preload("res://scenes/gameplay/ui/gameplay_ui_theme.tres")
const GOLD := Color(1, 0.84, 0.3)

var root_control: Control
var panel: PanelContainer
var title_label: Label
var list: VBoxContainer
var close_button: Button
## portal_id -> {"row", "button", "status"} for the open menu (read by tests).
var rows: Dictionary[StringName, Dictionary] = {}
var from_portal: TeleportPortal = null
var _player: PlayerController = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	layer = 20
	_build()
	root_control.visible = false


func is_open() -> bool:
	return root_control.visible


func open(portal: TeleportPortal, interactor: Node = null) -> void:
	if is_open() or portal == null:
		return
	var tree := get_tree()
	if tree.get_node_count_in_group(QuestJournal.MODAL_GROUP) > 0 or tree.get_node_count_in_group(DialogueBox.OPEN_GROUP) > 0:
		return
	var travel := FastTravel.find(tree)
	if travel != null and travel.travelling:
		return
	from_portal = portal
	_player = interactor as PlayerController
	if _player == null:
		_player = tree.get_first_node_in_group(CombatController.PLAYER_GROUP) as PlayerController
	if _player != null:
		_player.input_enabled = false
	title_label.text = portal.display_name
	_rebuild()
	root_control.visible = true
	add_to_group(QuestJournal.MODAL_GROUP)
	_focus_first()
	opened.emit(portal)


func close() -> void:
	if not is_open():
		return
	root_control.visible = false
	remove_from_group(QuestJournal.MODAL_GROUP)
	if _player != null:
		_player.set_deferred(&"input_enabled", true)
		_player = null
	from_portal = null
	closed.emit()


## Presses a destination's Travel button as the player would.
func choose(portal_id: StringName) -> void:
	var row: Dictionary = rows.get(portal_id, {})
	if not row.is_empty() and not (row["button"] as Button).disabled:
		(row["button"] as Button).pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact")):
		close()
		get_viewport().set_input_as_handled()


func _on_travel(portal_id: StringName) -> void:
	var from_id := from_portal.portal_id if from_portal != null else &""
	var travel := FastTravel.find(get_tree())
	close()
	if travel != null:
		travel.travel(from_id, portal_id)


# --- layout ---------------------------------------------------------------------

func _build() -> void:
	root_control = Control.new()
	root_control.name = "TeleportRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.theme = THEME
	add_child(root_control)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(dim)
	panel = PanelContainer.new()
	panel.name = "TeleportPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(480, 0)
	root_control.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	panel.add_child(body)
	var header := Label.new()
	header.text = "TELEPORT"
	header.add_theme_font_size_override(&"font_size", 14)
	header.add_theme_color_override(&"font_color", Color(0.75, 0.68, 1.0))
	body.add_child(header)
	title_label = Label.new()
	title_label.add_theme_font_size_override(&"font_size", 26)
	title_label.add_theme_color_override(&"font_color", GOLD)
	body.add_child(title_label)
	var hint := Label.new()
	hint.text = "Choose a destination. Only activated portals can be reached."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", Color(0.85, 0.82, 0.95))
	body.add_child(hint)
	list = VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 6)
	body.add_child(list)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 16)
	body.add_child(footer)
	var close_hint := Label.new()
	close_hint.text = "[%s] Close" % InputHints.key_for(&"ui_cancel")
	close_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(close_hint)
	InputPromptLabel.attach(close_hint)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	footer.add_child(close_button)


func _rebuild() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	rows.clear()
	var service := ExplorationService.find(get_tree())
	if service == null:
		return
	for location in service.get_locations(WorldLocation.Kind.PORTAL):
		if from_portal != null and location.location_id == from_portal.portal_id:
			continue
		list.add_child(_build_row(location, service))


func _build_row(location: WorldLocation, service: ExplorationService) -> Control:
	var id := location.location_id
	var active := service.is_portal_active(id)
	var known := service.is_discovered(id)
	var row := PanelContainer.new()
	row.name = String(id)
	row.theme_type_variation = &"ContractPanel"
	row.modulate = Color.WHITE if active else Color(1, 1, 1, 0.55)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	row.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"ContractTitle"
	name_label.text = location.display_name if known else "Unknown portal"
	text.add_child(name_label)
	var status := Label.new()
	status.theme_type_variation = &"ContractDetail"
	status.text = (location.subtitle if active else ("Not activated · visit it to unlock" if known else "Not discovered yet"))
	text.add_child(status)
	var button := Button.new()
	button.text = "Travel" if active else "Locked"
	button.disabled = not active
	button.custom_minimum_size = Vector2(110, 0)
	button.pressed.connect(_on_travel.bind(id))
	line.add_child(button)
	rows[id] = {"row": row, "button": button, "status": status}
	return row


func _focus_first() -> void:
	for id in rows:
		var button: Button = rows[id]["button"]
		if not button.disabled:
			button.grab_focus.call_deferred()
			return
	close_button.grab_focus.call_deferred()
