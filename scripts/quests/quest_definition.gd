class_name QuestDefinition
extends Resource
## Static, data-driven description of a quest. Authored as .tres in res://data/quests/.

@export var quest_id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
## npc_id of whoever hands out the contract (informational for UI).
@export var giver_id: StringName
## Delivery quests occupy the single active-delivery slot (MVP rule).
@export var is_delivery: bool = true
## Package carried for this quest. Its recipient_id is the delivery target.
@export var package: PackageDefinition
@export var recipient_name: String = ""
@export var destination_name: String = ""
@export var objectives: Array[QuestObjective] = []
@export var reward: QuestReward

@export_group("Recipient dialogue")
## Recipient says this while the quest is accepted/active but not yet delivered.
@export_multiline var recipient_waiting_line: String = ""
## Recipient says this after the reward was granted.
@export_multiline var recipient_after_line: String = ""


func get_recipient_id() -> StringName:
	return package.recipient_id if package != null else &""
