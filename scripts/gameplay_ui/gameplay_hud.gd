class_name GameplayHUD
extends CanvasLayer
## Composes the Phase 2 HUD widgets and hands them the player's PackageCarrier.
## Services (QuestManager, CourierWallet) are found by group if not assigned.

@export var player: PlayerController

@onready var quest_tracker: QuestTracker = $QuestTracker
@onready var package_indicator: PackageIndicator = $PackageIndicator
@onready var wallet_display: WalletDisplay = $WalletDisplay
@onready var quest_notification: QuestNotification = $QuestNotification


func _ready() -> void:
	if player == null:
		return
	var carrier := PackageCarrier.find_on(player)
	if carrier != null:
		package_indicator.bind_carrier(carrier)
		quest_notification.bind_carrier(carrier)
