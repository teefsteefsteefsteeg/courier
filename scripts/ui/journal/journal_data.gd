class_name JournalData
extends RefCounted
## View-model helpers for the quest journal. The journal only ever sees plain
## entry Dictionaries, so it does not depend on any quest system class:
##
##   id: StringName           title: String          status: String (STATUS_*)
##   giver: String            recipient: String      destination: String
##   description: String      reward: String
##   objectives: Array[Dictionary] of { text: String, done: bool, current: bool,
##                                      progress: int, required: int }
##
## `from_quest_manager()` adapts the gameplay QuestManager by duck typing (found
## through its "quest_manager" group), so this file compiles whether or not
## the quest system is present in the project.

const STATUS_ACTIVE := "active"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"
const QUEST_MANAGER_GROUP := &"quest_manager"
## Shown under a failed delivery (the quest board offers failed contracts again).
const RETRY_HINT := "You can take this contract again from the quest board."


static func find_quest_manager(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group(QUEST_MANAGER_GROUP)


static func is_archived(entry: Dictionary) -> bool:
	return entry.get("status", STATUS_ACTIVE) != STATUS_ACTIVE


## Builds entries for every accepted, in-progress, finished or failed quest.
## `name_for_id` maps an NPC id (StringName) to a display name.
static func from_quest_manager(manager: Node, name_for_id: Callable) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for quest_id: StringName in manager.call(&"get_quest_ids"):
		var definition: Object = manager.call(&"get_definition", quest_id)
		var state: Object = manager.call(&"get_state", quest_id)
		if definition == null or state == null:
			continue
		var status_key := _status_key(state)
		var status: String
		match status_key:
			"ACCEPTED", "ACTIVE":
				status = STATUS_ACTIVE
			"COMPLETED", "REWARDED":
				status = STATUS_COMPLETED
			"FAILED":
				status = STATUS_FAILED
			_:
				continue  # AVAILABLE quests live on the quest board, not in the journal.

		var objective_index: int = state.get(&"objective_index")
		var progress: PackedInt32Array = state.get(&"objective_progress")
		var objectives: Array[Dictionary] = []
		var definition_objectives: Array = definition.get(&"objectives")
		for i in definition_objectives.size():
			var objective: Object = definition_objectives[i]
			var finished := status == STATUS_COMPLETED or i < objective_index
			objectives.append({
				"text": str(objective.get(&"description")),
				"done": finished,
				"current": status == STATUS_ACTIVE and i == objective_index,
				"progress": progress[i] if i < progress.size() else (1 if finished else 0),
				"required": int(objective.get(&"required_count")),
			})

		var reward: Object = definition.get(&"reward")
		var description := str(definition.get(&"description"))
		var fail_reason := str(state.get(&"fail_reason"))
		if status == STATUS_FAILED and not fail_reason.is_empty():
			description += "\n\nFailed: %s" % fail_reason
		if status == STATUS_FAILED:
			description += "\n\n" + RETRY_HINT
		entries.append({
			"id": quest_id,
			"title": str(definition.get(&"title")),
			"status": status,
			"giver": name_for_id.call(definition.get(&"giver_id")),
			"recipient": str(definition.get(&"recipient_name")),
			"destination": str(definition.get(&"destination_name")),
			"description": description,
			"objectives": objectives,
			"reward": reward.call(&"describe") if reward != null and reward.has_method(&"describe") else "",
		})
	return entries


## Display name of the NPC whose `npc_id` (property or metadata) matches, else a prettified id.
static func npc_display_name(tree: SceneTree, npc_id: StringName) -> String:
	if npc_id == &"":
		return ""
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is NPC:
			var id: Variant = node.get(&"npc_id")
			if id == null or StringName(id) == &"":
				id = node.get_meta(&"npc_id", &"")
			if StringName(id) == npc_id:
				return (node as NPC).npc_name
		stack.append_array(node.get_children())
	return String(npc_id).capitalize()


static func _status_key(state: Object) -> String:
	# Resolve the enum value by name so the mapping survives enum reordering.
	var status_value: int = state.get(&"status")
	var script := state.get_script() as Script
	var enum_map: Dictionary = script.get_script_constant_map().get("Status", {}) if script != null else {}
	for key: String in enum_map:
		if enum_map[key] == status_value:
			return key
	return ""


## Preview entries shown when no quest system is running, so the journal can be
## laid out and play-tested on its own. Titles mirror the planned first quests.
static func sample_entries() -> Array[Dictionary]:
	return [
		{
			"id": &"sample_first_delivery", "title": "First Delivery", "status": STATUS_ACTIVE,
			"giver": "Postmaster Bram", "recipient": "Merchant Mira", "destination": "Village Market",
			"description": "Bram has trusted you with your very first parcel. Carry it across the square to Mira's stall before the noon rush.",
			"objectives": [
				{"text": "Talk to Postmaster Bram", "done": true, "current": false, "progress": 1, "required": 1},
				{"text": "Pick up the parcel from the sorting table", "done": true, "current": false, "progress": 1, "required": 1},
				{"text": "Deliver the parcel to Merchant Mira", "done": false, "current": true, "progress": 0, "required": 1},
			],
			"reward": "15 Gold, 5 Reputation",
		},
		{
			"id": &"sample_dragon_egg", "title": "The Dragon Egg", "status": STATUS_ACTIVE,
			"giver": "Postmaster Bram", "recipient": "Mage Elowen", "destination": "Moonstone Clearing",
			"description": "A warm, faintly humming egg must reach Mage Elowen in the Whisperwood. Keep it out of the cold.",
			"objectives": [
				{"text": "Collect the dragon egg", "done": false, "current": true, "progress": 0, "required": 1},
				{"text": "Reach the Moonstone Clearing", "done": false, "current": false, "progress": 0, "required": 1},
				{"text": "Hand the egg to Mage Elowen", "done": false, "current": false, "progress": 0, "required": 1},
			],
			"reward": "40 Gold, 10 Reputation",
		},
		{
			"id": &"sample_letters", "title": "Morning Letters", "status": STATUS_COMPLETED,
			"giver": "Postmaster Bram", "recipient": "Villager Pip", "destination": "Village Square",
			"description": "A bundle of letters for the villagers around the well.",
			"objectives": [
				{"text": "Deliver letters around the square", "done": true, "current": false, "progress": 3, "required": 3},
			],
			"reward": "5 Gold",
		},
		{
			"id": &"sample_potion", "title": "Unstable Potion", "status": STATUS_FAILED,
			"giver": "Postmaster Bram", "recipient": "Alchemist Corvin", "destination": "Alchemy Shop",
			"description": "A crate of volatile potions for Corvin.\n\nFailed: the crate was shaken one time too many.",
			"objectives": [
				{"text": "Pick up the potion crate", "done": true, "current": false, "progress": 1, "required": 1},
				{"text": "Deliver it to Alchemist Corvin without jostling", "done": false, "current": false, "progress": 0, "required": 1},
			],
			"reward": "25 Gold",
		},
	]
