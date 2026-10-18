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
var onboarding: Label


func _ready() -> void:
	onboarding = Label.new()
	onboarding.text = "Visit the post office quest board [E]\nAccept a delivery, then collect its package.\n! and ? above villagers mark who needs you.\n[J] Journal    [M] Map"
	onboarding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	onboarding.add_theme_font_size_override("font_size", 18)
	onboarding.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.06))
	onboarding.add_theme_constant_override("outline_size", 6)
	onboarding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(onboarding)
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
	_place(quest_tracker, Vector2.ZERO, Vector2(MARGIN, MARGIN), Vector2(width, maxf(100, quest_tracker.get_combined_minimum_size().y)))
	_place(onboarding, Vector2.ZERO, Vector2(MARGIN, MARGIN), Vector2(width, maxf(100, onboarding.get_combined_minimum_size().y)))
	onboarding.visible = not quest_tracker.visible
	_place(wallet_display, Vector2(1, 0), Vector2(-width - MARGIN, MARGIN), Vector2(width, maxf(46, wallet_display.get_combined_minimum_size().y)))
	var status_height := maxf(110, package_status_hud.get_node("Panel").get_combined_minimum_size().y)
	_place(package_status_hud, Vector2.ONE, Vector2(-width - MARGIN, -MARGIN - status_height), Vector2(width, status_height))
	var indicator_height := maxf(100, package_indicator.get_combined_minimum_size().y)
	var below := status_height + GAP if package_status_hud.visible else 0.0
	_place(package_indicator, Vector2.ONE, Vector2(-width - MARGIN, -MARGIN - below - indicator_height), Vector2(width, indicator_height))
	var map := get_node_or_null("Minimap")
	if map != null and map.get("compact") != null:
		var map_size := clampf(width * 0.6, 180, 220)
		_place(map.compact, Vector2(1, 0), Vector2(-map_size - MARGIN, MARGIN + wallet_display.size.y + GAP), Vector2(map_size, map_size))
		var extent := minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y) - 96.0
		map.expanded.custom_minimum_size = Vector2.ZERO
		_place(map.expanded, Vector2(0.5, 0.5), Vector2.ONE * -extent * 0.5, Vector2.ONE * extent)


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
