class_name QuestState
extends Resource
## Runtime progress for one quest. Owned and mutated only by QuestManager.
## Extends Resource so it can be serialized by the save system in a later phase.

enum Status { AVAILABLE, ACCEPTED, ACTIVE, COMPLETED, FAILED, REWARDED }

@export var quest_id: StringName
@export var status: Status = Status.AVAILABLE
## Index of the objective currently in progress (== objectives.size() when all done).
@export var objective_index: int = 0
@export var objective_progress: PackedInt32Array = PackedInt32Array()
@export var reward_granted: bool = false
@export var fail_reason: String = ""


func is_in_progress() -> bool:
	return status == Status.ACCEPTED or status == Status.ACTIVE


static func status_name(value: Status) -> String:
	return Status.keys()[value]


func to_dict() -> Dictionary:
	return {
		"quest_id": String(quest_id),
		"status": status_name(status),
		"objective_index": objective_index,
		"objective_progress": Array(objective_progress),
		"reward_granted": reward_granted,
		"fail_reason": fail_reason,
	}
