class_name QuestWaypoint
extends RefCounted
## Where the courier should head next for the quest in progress, for any contract
## (Phase 5F). Resolves the current objective to a world node by id:
## TALK / DELIVER -> the NPC, PICK_UP -> the source PackagePickup, REACH -> the
## DestinationArea. Once past pickup without the package in hand, a dropped package
## comes first. Used by the minimap; the Phase 4 Dragon Egg integration keeps its own
## route marker and takes precedence where it has one.


## Quest the HUD follows: the active delivery, else the first quest in progress.
static func current_quest_id(manager: QuestManager) -> StringName:
	if manager == null:
		return &""
	var quest_id := manager.get_active_delivery_id()
	if quest_id == &"":
		var in_progress := manager.get_in_progress_quests()
		quest_id = in_progress[0].quest_id if not in_progress.is_empty() else &""
	return quest_id


## Target node for the followed quest, or null when nothing is in progress.
static func target_for(tree: SceneTree, manager: QuestManager, carrier: PackageCarrier) -> Node3D:
	return target_for_quest(tree, manager, current_quest_id(manager), carrier)


static func target_for_quest(tree: SceneTree, manager: QuestManager, quest_id: StringName, carrier: PackageCarrier) -> Node3D:
	if manager == null or quest_id == &"":
		return null
	var objective := manager.get_current_objective(quest_id)
	if objective == null:
		return null
	match objective.type:
		QuestObjective.Type.TALK_TO_NPC:
			return NPC.find_by_id(tree, objective.target_id)
		QuestObjective.Type.PICK_UP_PACKAGE:
			return find_source_pickup(tree, objective.target_id)
	if not is_carrying(carrier, quest_id):
		var dropped := find_dropped_pickup(tree, quest_id)
		if dropped != null:
			return dropped
	match objective.type:
		QuestObjective.Type.REACH_DESTINATION:
			return find_destination(tree, objective.target_id)
		QuestObjective.Type.DELIVER_PACKAGE:
			return NPC.find_by_id(tree, objective.target_id)
	return null


## Short map label for the followed quest's target ("" when nothing is in progress).
static func label_for(tree: SceneTree, manager: QuestManager, carrier: PackageCarrier) -> String:
	var quest_id := current_quest_id(manager)
	var objective := manager.get_current_objective(quest_id) if quest_id != &"" else null
	if objective == null:
		return ""
	var target := target_for_quest(tree, manager, quest_id, carrier)
	if target is PackagePickup and (target as PackagePickup).is_dropped():
		return "Pick up the dropped %s" % (target as PackagePickup).package_definition.package_name
	return objective.description


static func is_carrying(carrier: PackageCarrier, quest_id: StringName) -> bool:
	return carrier != null and carrier.is_carrying() and carrier.get_package().get_quest_id() == quest_id


static func find_source_pickup(tree: SceneTree, package_id: StringName) -> PackagePickup:
	for node in tree.get_nodes_in_group(PackagePickup.GROUP):
		var pickup := node as PackagePickup
		if pickup != null and not pickup.is_dropped() and pickup.package_definition != null \
				and pickup.package_definition.package_id == package_id:
			return pickup
	return null


static func find_dropped_pickup(tree: SceneTree, quest_id: StringName) -> PackagePickup:
	for node in tree.get_nodes_in_group(PackagePickup.GROUP):
		var pickup := node as PackagePickup
		if pickup != null and pickup.is_dropped() and not pickup.is_queued_for_deletion() \
				and pickup.package_instance.get_quest_id() == quest_id:
			return pickup
	return null


static func find_destination(tree: SceneTree, destination_id: StringName) -> DestinationArea:
	for node in tree.get_nodes_in_group(DestinationArea.GROUP):
		var area := node as DestinationArea
		if area != null and area.destination_id == destination_id:
			return area
	return null
