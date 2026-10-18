class_name QuestNPCBehaviour
extends Node
## Child of an NPC. Makes the NPC take part in quests: completes TALK objectives,
## accepts/rejects deliveries, and picks dialogue from quest state.
## NPC calls get_interaction_line(); an empty string falls back to the NPC's default lines.
##
## Phase 5F feedback:
## - A floating quest marker above the NPC: "!" when a quest wants you to talk to them,
##   a bright "?" when you carry their package and can hand it over, a dim "?" while a
##   delivery for them is under way, and a short "✓" after a successful handover.
## - get_prompt_verb() turns the interaction prompt into "Deliver <package> to <NPC>"
##   when a handover would succeed.

enum Marker { NONE, TALK, DELIVER, AWAITING, THANKS }

signal delivery_accepted(package: PackageInstance)
signal delivery_refused(package: PackageInstance, result: QuestManager.DeliveryResult)
signal marker_changed(new_marker: Marker)

const MARKER_NAME := &"QuestMarker"
const MARKER_TEXT := {
	Marker.NONE: "",
	Marker.TALK: "!",
	Marker.DELIVER: "?",
	Marker.AWAITING: "?",
	Marker.THANKS: "✓",
}
const MARKER_COLORS := {
	Marker.NONE: Color(1, 1, 1, 0),
	Marker.TALK: Color(1.0, 0.82, 0.25),
	Marker.DELIVER: Color(1.0, 0.9, 0.35),
	Marker.AWAITING: Color(0.75, 0.78, 0.85, 0.75),
	Marker.THANKS: Color(0.55, 1.0, 0.55),
}

@export_multiline var wrong_recipient_line: String = "This isn't addressed to me. It's for %s."
@export_multiline var not_ready_line: String = "That's for me? Finish the route first, courier."

@export_group("Marker")
@export var show_marker: bool = true
## Marker height above the NPC origin.
@export_range(0.0, 6.0, 0.05, "suffix:m") var marker_height: float = 2.85
## Seconds between marker re-evaluations.
@export_range(0.0, 2.0, 0.05, "suffix:s") var marker_refresh_interval: float = 0.15
## Seconds the "✓" stays after a successful delivery.
@export_range(0.0, 10.0, 0.1, "suffix:s") var thanks_time: float = 2.5

## Current marker state (read by tests and the marker label).
var marker: Marker = Marker.NONE
var marker_label: Label3D = null
var _refresh_left: float = 0.0
var _thanks_left: float = 0.0
var _time: float = 0.0
var _carrier: PackageCarrier = null


func _ready() -> void:
	var npc := get_parent() as NPC
	if npc == null or not show_marker:
		return
	marker_label = _build_marker()
	# The NPC is still adding its children; attach the marker once it is done.
	npc.add_child.call_deferred(marker_label)


func _process(delta: float) -> void:
	if marker_label == null:
		return
	_time += delta
	if _thanks_left > 0.0:
		_thanks_left = maxf(_thanks_left - delta, 0.0)
		if _thanks_left <= 0.0:
			refresh_marker()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = marker_refresh_interval
		refresh_marker()
	marker_label.position.y = marker_height + sin(_time * 2.6) * 0.08


func get_interaction_line(npc: NPC, interactor: Node) -> String:
	var manager := QuestManager.find(get_tree())
	if manager == null or npc.npc_id == &"":
		return ""
	var carrier := PackageCarrier.find_on(interactor)

	# 1. Delivery attempt with whatever the player carries.
	if carrier != null and carrier.is_carrying():
		var package := carrier.get_package()
		var result := manager.try_deliver(npc.npc_id, package)
		if result == QuestManager.DeliveryResult.OK:
			carrier.remove_package(&"delivered")
			delivery_accepted.emit(package)
			_thanks_left = thanks_time
			refresh_marker()
			var definition := manager.get_definition(package.get_quest_id())
			var deliver_objective := _last_deliver_objective(definition)
			return deliver_objective.completion_line if deliver_objective != null and not deliver_objective.completion_line.is_empty() else "Thank you, courier!"
		delivery_refused.emit(package, result)
		if result == QuestManager.DeliveryResult.WRONG_RECIPIENT:
			var target_quest := manager.get_definition(package.get_quest_id())
			var recipient := target_quest.recipient_name if target_quest != null else "someone else"
			return wrong_recipient_line % recipient if wrong_recipient_line.contains("%s") else wrong_recipient_line
		if result == QuestManager.DeliveryResult.NOT_READY:
			return not_ready_line

	# 2. Talk objectives.
	var talked := manager.notify_talked_to(npc.npc_id)
	if talked != null:
		refresh_marker()
		return talked.completion_line

	# 3. Recipient waiting for a package.
	for definition in manager.get_quests_awaiting_recipient(npc.npc_id):
		if not definition.recipient_waiting_line.is_empty():
			return definition.recipient_waiting_line

	# 4. Recipient after a finished delivery.
	var rewarded := manager.get_rewarded_quests_for_recipient(npc.npc_id)
	if not rewarded.is_empty() and not rewarded[-1].recipient_after_line.is_empty():
		return rewarded[-1].recipient_after_line
	return ""


## Prompt verb for NPC.get_interaction_prompt(): "Deliver <package> to" when handing the
## carried package to this NPC would succeed right now, otherwise "" (default prompt).
func get_prompt_verb(npc: NPC, interactor: Node) -> String:
	var manager := QuestManager.find(get_tree())
	var carrier := PackageCarrier.find_on(interactor)
	if manager == null or carrier == null or not carrier.is_carrying() or npc.npc_id == &"":
		return ""
	if manager.check_delivery(npc.npc_id, carrier.get_package()) != QuestManager.DeliveryResult.OK:
		return ""
	return "Deliver %s to" % carrier.get_package().get_display_name()


## Marker for npc_id given the quest state and the package the courier carries (may be null).
static func marker_for(manager: QuestManager, npc_id: StringName, carried: PackageInstance) -> Marker:
	if manager == null or npc_id == &"":
		return Marker.NONE
	if carried != null and manager.check_delivery(npc_id, carried) == QuestManager.DeliveryResult.OK:
		return Marker.DELIVER
	if manager.get_quest_waiting_to_talk(npc_id) != null:
		return Marker.TALK
	if not manager.get_quests_awaiting_recipient(npc_id).is_empty():
		return Marker.AWAITING
	return Marker.NONE


## Re-evaluates the marker now (also runs every marker_refresh_interval).
func refresh_marker() -> void:
	var npc := get_parent() as NPC
	if npc == null:
		return
	var next: Marker = Marker.THANKS if _thanks_left > 0.0 else Marker.NONE
	if next == Marker.NONE:
		var carrier := _find_carrier()
		next = marker_for(QuestManager.find(get_tree()), npc.npc_id, carrier.get_package() if carrier != null else null)
	if marker_label != null:
		marker_label.text = MARKER_TEXT[next]
		marker_label.modulate = MARKER_COLORS[next]
		marker_label.visible = show_marker and next != Marker.NONE
	if next != marker:
		marker = next
		marker_changed.emit(marker)


static func marker_name(value: int) -> String:
	return Marker.keys()[value] if value >= 0 and value < Marker.size() else "?"


func _build_marker() -> Label3D:
	var label := Label3D.new()
	label.name = MARKER_NAME
	label.position = Vector3(0.0, marker_height, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.01
	label.font_size = 72
	label.outline_size = 14
	label.outline_modulate = Color(0.08, 0.06, 0.12, 1.0)
	label.render_priority = 1
	label.text = ""
	label.visible = false
	return label


## The courier's carrier: the combat player group first, then any PlayerController.
func _find_carrier() -> PackageCarrier:
	if _carrier != null and is_instance_valid(_carrier) and _carrier.is_inside_tree():
		return _carrier
	_carrier = null
	var body := get_tree().get_first_node_in_group(CombatController.PLAYER_GROUP)
	if body == null:
		var scene := get_tree().current_scene
		if scene != null:
			var players := scene.find_children("*", "PlayerController", true, false)
			body = players[0] if not players.is_empty() else null
	if body != null:
		_carrier = PackageCarrier.find_on(body)
	return _carrier


func _last_deliver_objective(definition: QuestDefinition) -> QuestObjective:
	if definition == null:
		return null
	for i in range(definition.objectives.size() - 1, -1, -1):
		if definition.objectives[i].type == QuestObjective.Type.DELIVER_PACKAGE:
			return definition.objectives[i]
	return null
