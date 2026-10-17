class_name QuestReward
extends Resource
## What a quest pays out once. Granted by QuestManager exactly one time.

@export_range(0, 100000) var gold: int = 0
@export_range(-1000, 1000) var reputation: int = 0


func describe() -> String:
	var parts: PackedStringArray = []
	if gold != 0:
		parts.append("%d Gold" % gold)
	if reputation != 0:
		parts.append("%d Reputation" % reputation)
	return ", ".join(parts) if not parts.is_empty() else "None"
