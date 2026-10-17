class_name QuestBoard
extends StaticBody3D
## Interactable post-office board. Pressing E emits `opened`; QuestBoardUI (or any
## other UI) listens via the "quest_board" group and shows the contracts.

signal opened(board: QuestBoard, interactor: Node)

const GROUP := &"quest_board"

@export var board_name: String = "Quest Board"
## quest_ids offered here. Empty = every quest registered in QuestManager.
@export var offered_quest_ids: Array[StringName] = []

@onready var interactable: Interactable = $Interactable


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	interactable.prompt_verb = "Read"
	interactable.display_name = board_name
	interactable.interacted.connect(_on_interacted)


func get_offered_quests(manager: QuestManager) -> Array[QuestDefinition]:
	var result: Array[QuestDefinition] = []
	var ids := offered_quest_ids if not offered_quest_ids.is_empty() else manager.get_quest_ids()
	for id in ids:
		var definition := manager.get_definition(id)
		if definition != null:
			result.append(definition)
	return result


func _on_interacted(interactor: Node) -> void:
	opened.emit(self, interactor)
