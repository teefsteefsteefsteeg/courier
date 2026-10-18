class_name QuestNotification
extends Control
## Queued toast messages for quest and package events.
## Phase 5F: each toast has a kind (info, success, warning, rank) that tints its text,
## refused deliveries explain what is missing, and courier rank-ups are announced.

const KIND_INFO := &"info"
const KIND_SUCCESS := &"success"
const KIND_WARNING := &"warning"
const KIND_RANK := &"rank"
const KIND_COLORS := {
	&"info": Color(1, 1, 1),
	&"success": Color(0.6, 1.0, 0.6),
	&"warning": Color(1.0, 0.72, 0.4),
	&"rank": Color(1.0, 0.86, 0.4),
}

@export var quest_manager: QuestManager
@export var carrier: PackageCarrier
@export var wallet: CourierWallet
@export_range(0.5, 10.0, 0.1, "suffix:s") var display_time: float = 3.0
## Display time used while more messages are waiting.
@export_range(0.2, 10.0, 0.1, "suffix:s") var queued_display_time: float = 1.0

@onready var panel: Control = %ToastPanel
@onready var label: Label = %ToastLabel

## Every message shown, in order (read by tests and debugging).
var history: PackedStringArray = []
## Kind of each message in history, same order.
var kind_history: Array[StringName] = []
## Kind of the toast on screen (or last shown).
var current_kind: StringName = KIND_INFO
var _queue: PackedStringArray = []
var _kind_queue: Array[StringName] = []
var _time_left: float = 0.0


func _ready() -> void:
	panel.visible = false
	if carrier != null:
		bind_carrier(carrier)
	_connect.call_deferred()


func _connect() -> void:
	if quest_manager == null:
		quest_manager = QuestManager.find(get_tree())
	if quest_manager != null:
		quest_manager.quest_accepted.connect(func(id: StringName): push_message("Contract accepted: %s" % _title(id), KIND_INFO))
		quest_manager.quest_failed.connect(func(id: StringName, reason: String): push_message("Delivery failed: %s%s" % [_title(id), (" (%s)" % reason) if not reason.is_empty() else ""], KIND_WARNING))
		quest_manager.quest_rewarded.connect(_on_rewarded)
		quest_manager.delivery_rejected.connect(_on_rejected)
	if wallet == null:
		wallet = CourierWallet.find(get_tree())
	if wallet != null:
		# Deferred: the wallet is paid before quest_rewarded fires, and the rank-up
		# should follow the "Delivery complete" toast.
		wallet.rank_changed.connect(_on_rank_changed, CONNECT_DEFERRED)


func bind_carrier(new_carrier: PackageCarrier) -> void:
	carrier = new_carrier
	carrier.pickup_blocked.connect(func(_p, reason: String): push_message(reason, KIND_WARNING))
	carrier.package_picked_up.connect(func(p: PackageInstance): push_message("Picked up: %s" % p.definition.package_name, KIND_INFO))
	carrier.package_dropped.connect(func(p: PackageInstance): push_message("Dropped: %s" % p.definition.package_name, KIND_WARNING))


func push_message(text: String, kind: StringName = KIND_INFO) -> void:
	history.append(text)
	kind_history.append(kind)
	_queue.append(text)
	_kind_queue.append(kind)
	if not panel.visible:
		_show_next()
	else:
		_time_left = minf(_time_left, queued_display_time)


## Messages waiting behind the one on screen.
func get_queued_count() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	var width := minf(520.0, get_viewport().get_visible_rect().size.x * 0.4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	offset_top = 186.0
	if not panel.visible:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		panel.visible = false
		return
	label.text = _queue[0]
	_queue.remove_at(0)
	current_kind = KIND_INFO
	if not _kind_queue.is_empty():
		current_kind = _kind_queue[0]
		_kind_queue.remove_at(0)
	var color: Color = KIND_COLORS.get(current_kind, KIND_COLORS[KIND_INFO])
	label.add_theme_color_override(&"font_color", color)
	# Move faster through a backlog so toasts stay close to the events that caused them.
	_time_left = display_time if _queue.is_empty() else minf(display_time, queued_display_time)
	panel.visible = true


func _on_rewarded(id: StringName, reward: QuestReward) -> void:
	push_message("Delivery complete: %s!  +%s" % [_title(id), reward.describe() if reward != null else ""], KIND_SUCCESS)


func _on_rejected(quest_id: StringName, _npc_id: StringName, result: QuestManager.DeliveryResult) -> void:
	match result:
		QuestManager.DeliveryResult.WRONG_RECIPIENT:
			var definition := quest_manager.get_definition(quest_id)
			if definition != null and not definition.recipient_name.is_empty():
				push_message("Wrong recipient. Check the address: %s, %s." % [definition.recipient_name, definition.destination_name], KIND_WARNING)
			else:
				push_message("Wrong recipient. Check the address.", KIND_WARNING)
		QuestManager.DeliveryResult.NOT_READY:
			var objective := quest_manager.get_current_objective(quest_id)
			if objective != null:
				push_message("Not yet: %s" % objective.description, KIND_WARNING)


func _on_rank_changed(new_rank: int, old_rank: int) -> void:
	if new_rank > old_rank:
		push_message("Rank up: %s!" % CourierWallet.rank_title(new_rank), KIND_RANK)
	else:
		push_message("Your standing fell: %s." % CourierWallet.rank_title(new_rank), KIND_WARNING)


func _title(id: StringName) -> String:
	var definition := quest_manager.get_definition(id)
	return definition.title if definition != null else String(id)
