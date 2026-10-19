class_name HouseDoor
extends Node3D
## The front door of an enterable building (Phase 8): "[E] Enter <place_name>" takes the
## courier into interior_id (a WorldRouter region with its own scene) at its "Entry"
## spawn. The courier comes back out here, at the Exit marker (a child placed in front of
## the door, outside the building's collider). Needs an Interactable child.

const GROUP := &"house_doors"

@export var interior_id: StringName
@export var place_name: String = "the house"

var interactable: Interactable


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for child in get_children():
		if child is Interactable:
			interactable = child
	if interactable == null:
		push_warning("HouseDoor %s has no Interactable" % name)
		return
	interactable.prompt_verb = "Enter"
	interactable.display_name = place_name
	interactable.interacted.connect(enter)


## Where the courier stands when leaving the building.
func get_exit_point() -> Vector3:
	var exit := get_node_or_null(^"Exit") as Node3D
	return exit.global_position if exit != null else global_position + global_basis.z * 1.2


## Goes in (also used by tests). False when the router refuses (a crossing is under way).
func enter(interactor: Node = null) -> bool:
	var router := get_tree().get_first_node_in_group(&"phase6_router")
	if router == null:
		return false
	return bool(router.call(&"travel", interior_id, &"Entry", interactor, get_exit_point()))
