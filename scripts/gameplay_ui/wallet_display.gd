class_name WalletDisplay
extends Control
## Gold and reputation counter.

@export var wallet: CourierWallet

@onready var gold_label: Label = %GoldLabel
@onready var reputation_label: Label = %ReputationLabel


func _ready() -> void:
	_connect.call_deferred()


func _connect() -> void:
	if wallet == null:
		wallet = CourierWallet.find(get_tree())
	if wallet == null:
		visible = false
		return
	wallet.gold_changed.connect(func(_v, _d): refresh())
	wallet.reputation_changed.connect(func(_v, _d): refresh())
	refresh()


func refresh() -> void:
	gold_label.text = "Gold: %d" % wallet.gold
	reputation_label.text = "Reputation: %d" % wallet.reputation
