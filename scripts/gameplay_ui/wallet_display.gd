class_name WalletDisplay
extends Control
## Gold and reputation counter, plus (Phase 5F) the courier rank with progress to the
## next rank and a short-lived "+gold / +rep" delta after each payout.

@export var wallet: CourierWallet
## Seconds the payout delta stays on screen (it fades over the last third).
@export_range(0.5, 10.0, 0.1, "suffix:s") var delta_display_time: float = 3.0

@onready var gold_label: Label = %GoldLabel
@onready var reputation_label: Label = %ReputationLabel
@onready var rank_label: Label = %RankLabel
@onready var delta_label: Label = %DeltaLabel
@onready var rank_bar: ProgressBar = %RankBar

var _gold_delta: int = 0
var _reputation_delta: int = 0
var _delta_left: float = 0.0


func _ready() -> void:
	delta_label.text = ""
	_connect.call_deferred()


func _connect() -> void:
	if wallet == null:
		wallet = CourierWallet.find(get_tree())
	if wallet == null:
		visible = false
		return
	wallet.gold_changed.connect(func(_v, delta: int): _on_changed(delta, 0))
	wallet.reputation_changed.connect(func(_v, delta: int): _on_changed(0, delta))
	refresh()


func _process(delta: float) -> void:
	if _delta_left <= 0.0:
		return
	_delta_left -= delta
	var fade := delta_display_time / 3.0
	delta_label.modulate.a = clampf(_delta_left / fade, 0.0, 1.0)
	if _delta_left <= 0.0:
		clear_delta()


func refresh() -> void:
	gold_label.text = "Gold: %d" % wallet.gold
	reputation_label.text = "Reputation: %d" % wallet.reputation
	var to_next := wallet.get_reputation_to_next_rank()
	rank_label.text = wallet.get_rank_title() if to_next <= 0 else "%s  (%d to next)" % [wallet.get_rank_title(), to_next]
	rank_bar.value = wallet.get_rank_progress()


## True while a payout delta is on screen.
func is_showing_delta() -> bool:
	return _delta_left > 0.0 and not delta_label.text.is_empty()


func clear_delta() -> void:
	_gold_delta = 0
	_reputation_delta = 0
	_delta_left = 0.0
	delta_label.text = ""
	delta_label.modulate.a = 1.0


func _on_changed(gold_delta: int, reputation_delta: int) -> void:
	# Gold and reputation of one payout arrive as two signals; merge them into one line.
	_gold_delta += gold_delta
	_reputation_delta += reputation_delta
	var parts: PackedStringArray = []
	if _gold_delta != 0:
		parts.append("%+d g" % _gold_delta)
	if _reputation_delta != 0:
		parts.append("%+d rep" % _reputation_delta)
	delta_label.text = "  ".join(parts)
	var gaining := _gold_delta >= 0 and _reputation_delta >= 0
	delta_label.add_theme_color_override(&"font_color", Color(0.55, 1.0, 0.55) if gaining else Color(1.0, 0.5, 0.45))
	delta_label.modulate.a = 1.0
	_delta_left = delta_display_time
	refresh()
