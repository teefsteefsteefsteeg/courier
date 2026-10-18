class_name Interactable
extends Area3D
## Marks something the player can interact with. Put it on the "interactable"
## physics layer (layer 4) so an InteractionDetector can find it. The owner
## listens to `interacted` and decides what actually happens.

signal interacted(interactor: Node)

## Verb phrase shown before the name, e.g. "Talk to", "Open", "Pick up".
@export var prompt_verb: String = "Talk to"
## Name shown in the prompt, e.g. "Postmaster Bram".
@export var display_name: String = "Someone"
@export var enabled: bool = true


func _ready() -> void:
	monitoring = false
	monitorable = true


func get_prompt_text() -> String:
	return "%s %s" % [prompt_verb, display_name]


## Prompt for a specific interactor. The owner (parent) may supply a context prompt
## through get_interaction_prompt(interactor) -> String, e.g. an NPC that is waiting
## for the package the interactor carries; empty falls back to get_prompt_text().
func get_prompt_text_for(interactor: Node) -> String:
	var owner_node := get_parent()
	if interactor != null and owner_node != null and owner_node.has_method(&"get_interaction_prompt"):
		var text: String = owner_node.call(&"get_interaction_prompt", interactor)
		if not text.is_empty():
			return text
	return get_prompt_text()


func interact(interactor: Node) -> void:
	if not enabled:
		return
	interacted.emit(interactor)
