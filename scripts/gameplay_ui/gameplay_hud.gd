class_name GameplayHUD
extends CanvasLayer
## Composes the Phase 2 HUD widgets and hands them the player's PackageCarrier.
## Services (QuestManager, CourierWallet) are found by group if not assigned.

@export var player: PlayerController

@onready var quest_tracker: QuestTracker = $QuestTracker
@onready var package_indicator: PackageIndicator = $PackageIndicator
@onready var wallet_display: WalletDisplay = $WalletDisplay
@onready var quest_notification: QuestNotification = $QuestNotification
@onready var package_status_hud: PackageStatusHUD = $PackageStatusHUD

const MARGIN := 16.0
const GAP := 12.0
## Space under the tool HUD for the interaction prompt (bottom centre).
const TOOL_HUD_BOTTOM := 150.0
var onboarding: Label
## Keyboard guide (actual bindings, keycaps only), bottom-left.
var movement_guide: MovementGuide
## Weapon quick slots (keys 1-5), bottom-right under the package panels.
var quick_weapon_bar: QuickWeaponBar
## Equipment window (Tab): owned gear and quick-slot assignment.
var equipment_ui: EquipmentUI
## Fast-travel destinations, opened by an active TeleportPortal.
var teleport_menu: TeleportMenu
## Tool job / fishing progress (Phase 5H), bottom centre above the interaction prompt.
var tool_action_hud: ToolActionHUD
var _combat_panel: Control = null
var _combat_scan_left: float = 0.0


func _ready() -> void:
	onboarding = Label.new()
	# Journal and map keys are on the keyboard guide (MovementGuide), so no text for them here.
	onboarding.text = "[%s] Read the quest board at the post office\nAccept a delivery, then collect its package.\n! and ? mark villagers who need you." % InputHints.key_for(&"interact")
	onboarding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	onboarding.add_theme_font_size_override("font_size", 18)
	onboarding.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.06))
	onboarding.add_theme_constant_override("outline_size", 6)
	onboarding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(onboarding)
	InputPromptLabel.attach(onboarding)
	movement_guide = MovementGuide.new()
	movement_guide.name = "MovementGuide"
	add_child(movement_guide)
	quick_weapon_bar = QuickWeaponBar.new()
	quick_weapon_bar.name = "QuickWeaponBar"
	quick_weapon_bar.player = player
	add_child(quick_weapon_bar)
	quick_weapon_bar.add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	equipment_ui = EquipmentUI.new()
	equipment_ui.name = "EquipmentUI"
	add_child(equipment_ui)
	teleport_menu = TeleportMenu.new()
	teleport_menu.name = "TeleportMenu"
	add_child(teleport_menu)
	tool_action_hud = ToolActionHUD.new()
	tool_action_hud.name = "ToolActionHUD"
	tool_action_hud.player = player
	tool_action_hud.notifier = quest_notification
	add_child(tool_action_hud)
	tool_action_hud.add_to_group(QuestJournal.HIDDEN_WHILE_OPEN_GROUP)
	# World-anchored input prompts stay clear of these panels.
	for widget: Control in [quest_tracker, wallet_display, package_indicator, quest_notification.panel, package_status_hud.get_node("Panel"), onboarding, movement_guide, quick_weapon_bar, tool_action_hud]:
		widget.add_to_group(InputPrompt.AVOID_GROUP)
	if player == null:
		return
	var carrier := PackageCarrier.find_on(player)
	if carrier != null:
		package_indicator.bind_carrier(carrier)
		quest_notification.bind_carrier(carrier)
		quest_tracker.bind_carrier(carrier)
		if not carrier.carried_package_changed.is_connected(_on_carried_package_changed):
			carrier.carried_package_changed.connect(_on_carried_package_changed)
		_on_carried_package_changed(carrier.get_package())


func _process(_delta: float) -> void:
	# Corner anchors follow the viewport. Heights come from current content,
	# including wrapped objectives and conditional package warning rows.
	var width := clampf(get_viewport().get_visible_rect().size.x * 0.25, 300.0, 380.0)
	# Top-left column: the courier status panel (Phase 4 combat HUD), then the tracker.
	var left_top := MARGIN
	var status := _find_combat_panel(_delta)
	if status != null and status.is_visible_in_tree():
		left_top = status.get_global_rect().end.y + GAP
	_place(quest_tracker, Vector2.ZERO, Vector2(MARGIN, left_top), Vector2(width, maxf(100, quest_tracker.get_combined_minimum_size().y)))
	_place(onboarding, Vector2.ZERO, Vector2(MARGIN, left_top), Vector2(width, maxf(100, onboarding.get_combined_minimum_size().y)))
	onboarding.visible = not quest_tracker.visible
	_place(wallet_display, Vector2(1, 0), Vector2(-width - MARGIN, MARGIN), Vector2(width, maxf(46, wallet_display.get_combined_minimum_size().y)))
	# Bottom-right column, from the bottom: weapon quick slots, package status, package.
	var bar_height := quick_weapon_bar.get_combined_minimum_size().y
	_place(quick_weapon_bar, Vector2.ONE, Vector2(-width - MARGIN, -MARGIN - bar_height), Vector2(width, bar_height))
	var bar_space := bar_height + GAP if quick_weapon_bar.visible else 0.0
	var status_height := maxf(110, package_status_hud.get_node("Panel").get_combined_minimum_size().y)
	_place(package_status_hud, Vector2.ONE, Vector2(-width - MARGIN, -MARGIN - bar_space - status_height), Vector2(width, status_height))
	var indicator_height := maxf(100, package_indicator.get_combined_minimum_size().y)
	var below := bar_space + (status_height + GAP if package_status_hud.visible else 0.0)
	_place(package_indicator, Vector2.ONE, Vector2(-width - MARGIN, -MARGIN - below - indicator_height), Vector2(width, indicator_height))
	var map := get_node_or_null("Minimap")
	if map != null and map.get("compact") != null:
		var map_size := clampf(width * 0.6, 180, 220)
		_place(map.compact, Vector2(1, 0), Vector2(-map_size - MARGIN, MARGIN + wallet_display.size.y + GAP), Vector2(map_size, map_size))
		var extent := minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y) - 96.0
		map.expanded.custom_minimum_size = Vector2.ZERO
		_place(map.expanded, Vector2(0.5, 0.5), Vector2.ONE * -extent * 0.5, Vector2.ONE * extent)
	_place_movement_guide(_delta)
	var view := get_viewport().get_visible_rect().size
	var tool_size := tool_action_hud.get_combined_minimum_size()
	_place(tool_action_hud, Vector2(0.5, 1), Vector2(-tool_size.x * 0.5, -TOOL_HUD_BOTTOM - tool_size.y), tool_size)
	if view.x < 1100:
		# Narrow windows: the bottom corners' panels reach the middle; sit above them.
		_place(tool_action_hud, Vector2(0.5, 0.5), Vector2(-tool_size.x * 0.5, view.y * 0.12), tool_size)


## Bottom-left (stacked above the courier status panel if that is ever at the bottom).
## Hidden when the UI setting is off, or when there is no room clear of the other HUD
## panels (very short windows, or the dialogue box reaching the left edge).
func _place_movement_guide(delta: float) -> void:
	var guide_size := movement_guide.get_combined_minimum_size()
	var view := get_viewport().get_visible_rect().size
	var bottom := view.y - MARGIN
	var combat := _find_combat_panel(delta)
	if combat != null and combat.is_visible_in_tree() and combat.get_global_rect().position.y > view.y * 0.5:
		bottom = minf(bottom, combat.get_global_rect().position.y - GAP)
	_place(movement_guide, Vector2.ZERO, Vector2(MARGIN, bottom - guide_size.y), guide_size)
	var rect := Rect2(Vector2(MARGIN, bottom - guide_size.y), guide_size)
	movement_guide.visible = UISettings.show_movement_guide() and _fits_clear(rect, combat)


func _fits_clear(rect: Rect2, combat: Control) -> bool:
	if rect.position.y < MARGIN:
		return false
	if combat != null and combat.is_visible_in_tree() and rect.intersects(combat.get_global_rect()):
		return false
	for node in get_tree().get_nodes_in_group(InputPrompt.AVOID_GROUP):
		var control := node as Control
		if control != null and control != movement_guide and control.is_visible_in_tree() \
				and rect.grow(GAP * 0.5).intersects(control.get_global_rect()):
			return false
	return true


## The Phase 4 combat HUD panel (bottom-left), found once it exists.
func _find_combat_panel(delta: float) -> Control:
	if _combat_panel != null and is_instance_valid(_combat_panel):
		return _combat_panel
	_combat_scan_left -= delta
	if _combat_scan_left > 0.0:
		return null
	_combat_scan_left = 1.0
	var scene := get_tree().current_scene
	var combat_hud := scene.find_child("CombatHUD", true, false) if scene != null else null
	if combat_hud != null and combat_hud.get("panel") is Control:
		_combat_panel = combat_hud.get("panel")
	return _combat_panel


static func _place(control: Control, anchor: Vector2, origin: Vector2, extent: Vector2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = origin.x
	control.offset_top = origin.y
	control.offset_right = origin.x + extent.x
	control.offset_bottom = origin.y + extent.y


func _on_carried_package_changed(package: PackageInstance) -> void:
	if package == null:
		package_status_hud.unbind_package()
	else:
		package_status_hud.bind_package(package)
