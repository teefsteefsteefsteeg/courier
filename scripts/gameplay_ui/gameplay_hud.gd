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


func _ready() -> void:
	if player == null:
		return
	var carrier := PackageCarrier.find_on(player)
	if carrier != null:
		package_indicator.bind_carrier(carrier)
		quest_notification.bind_carrier(carrier)
		if not carrier.carried_package_changed.is_connected(_on_carried_package_changed):
			carrier.carried_package_changed.connect(_on_carried_package_changed)
		_on_carried_package_changed(carrier.get_package())


func _on_carried_package_changed(package: PackageInstance) -> void:
	if package == null:
		package_status_hud.unbind_package()
	else:
		package_status_hud.bind_package(package)
