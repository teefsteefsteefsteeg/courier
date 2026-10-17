class_name QuestNPCBehaviour
extends Node
## Child of an NPC. Makes the NPC take part in quests: completes TALK objectives,
## accepts/rejects deliveries, and picks dialogue from quest state.
## NPC calls get_interaction_line(); an empty string falls back to the NPC's default lines.

signal delivery_accepted(package: PackageInstance)
signal delivery_refused(package: PackageInstance, result: QuestManager.DeliveryResult)

@export_multiline var wrong_recipient_line: String = "This isn't addressed to me. It's for %s."
@export_multiline var not_ready_line: String = "That's for me? Finish the route first, courier."


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


func _last_deliver_objective(definition: QuestDefinition) -> QuestObjective:
	if definition == null:
		return null
	for i in range(definition.objectives.size() - 1, -1, -1):
		if definition.objectives[i].type == QuestObjective.Type.DELIVER_PACKAGE:
			return definition.objectives[i]
	return null
