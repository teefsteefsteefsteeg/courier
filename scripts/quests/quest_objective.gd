class_name QuestObjective
extends Resource
## One step of a quest. Objectives are completed strictly in order.

enum Type { TALK_TO_NPC, PICK_UP_PACKAGE, REACH_DESTINATION, DELIVER_PACKAGE }

@export var type: Type = Type.TALK_TO_NPC
## TALK_TO_NPC / DELIVER_PACKAGE: npc_id. PICK_UP_PACKAGE: package_id. REACH_DESTINATION: destination_id.
@export var target_id: StringName
## Shown in the quest tracker, e.g. "Deliver the parcel to Merchant Mira".
@export var description: String = ""
@export_range(1, 99) var required_count: int = 1
## Optional line the target NPC says when this objective completes (talk / deliver).
@export_multiline var completion_line: String = ""
