class_name NPCAnimator
extends Node
## Plays a talk gesture on an NPC's KayKitCharacter whenever the NPC speaks.

@export var character: KayKitCharacter


func _ready() -> void:
	var npc := get_parent() as NPC
	if npc != null and character != null:
		npc.spoke.connect(func(_name: String, _line: String) -> void: character.play_once(&"interact"))
