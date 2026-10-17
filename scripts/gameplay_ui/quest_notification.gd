class_name QuestNotification
extends Control
## Queued toast messages for quest and package events.

@export var quest_manager: QuestManager
@export var carrier: PackageCarrier
@export_range(0.5, 10.0, 0.1, "suffix:s") var display_time: float = 3.0
## Display time used while more messages are waiting.
@export_range(0.2, 10.0, 0.1, "suffix:s") var queued_display_time: float = 1.0

@onready var panel: Control = %ToastPanel
@onready var label: Label = %ToastLabel

## Every message shown, in order (read by tests and debugging).
var history: PackedStringArray = []
var _queue: PackedStringArray = []
var _time_left: float = 0.0


func _ready() -> void:
	panel.visible = false
	if carrier != null:
		bind_carrier(carrier)
	_connect.call_deferred()


func _connect() -> void:
	if quest_manager == null:
		quest_manager = QuestManager.find(get_tree())
	if quest_manager == null:
		return
	quest_manager.quest_accepted.connect(func(id: StringName): push_message("Contract accepted: %s" % _title(id)))
	quest_manager.quest_failed.connect(func(id: StringName, reason: String): push_message("Delivery failed: %s%s" % [_title(id), (" (%s)" % reason) if not reason.is_empty() else ""]))
	quest_manager.quest_rewarded.connect(_on_rewarded)
	quest_manager.delivery_rejected.connect(_on_rejected)


func bind_carrier(new_carrier: PackageCarrier) -> void:
	carrier = new_carrier
	carrier.pickup_blocked.connect(func(_p, reason: String): push_message(reason))
	carrier.package_picked_up.connect(func(p: PackageInstance): push_message("Picked up: %s" % p.definition.package_name))
	carrier.package_dropped.connect(func(p: PackageInstance): push_message("Dropped: %s" % p.definition.package_name))


func push_message(text: String) -> void:
	history.append(text)
	_queue.append(text)
	if not panel.visible:
		_show_next()
	else:
		_time_left = minf(_time_left, queued_display_time)


func _process(delta: float) -> void:
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
	# Move faster through a backlog so toasts stay close to the events that caused them.
	_time_left = display_time if _queue.is_empty() else minf(display_time, queued_display_time)
	panel.visible = true


func _on_rewarded(id: StringName, reward: QuestReward) -> void:
	push_message("Delivery complete: %s!  +%s" % [_title(id), reward.describe() if reward != null else ""])


func _on_rejected(_quest_id: StringName, _npc_id: StringName, result: QuestManager.DeliveryResult) -> void:
	if result == QuestManager.DeliveryResult.WRONG_RECIPIENT:
		push_message("Wrong recipient. Check the address.")


func _title(id: StringName) -> String:
	var definition := quest_manager.get_definition(id)
	return definition.title if definition != null else String(id)
