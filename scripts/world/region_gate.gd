class_name RegionGate
extends Node3D
## A gateway between outdoor regions (Phase 8): "[E] Travel to <place_name>" takes the
## courier to target_region at its spawn marker through the WorldRouter. Leaving the
## village, the courier comes back at this gate's Exit marker (a child in front of the
## gate on the village side). Needs an Interactable child.

const GROUP := &"region_gates"

@export var target_region: StringName
@export var spawn: StringName = &"Arrival"
@export var place_name: String = "the next region"

var interactable: Interactable


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	for child in get_children():
		if child is Interactable:
			interactable = child
	if interactable == null:
		push_warning("RegionGate %s has no Interactable" % name)
		return
	interactable.prompt_verb = "Travel to"
	interactable.display_name = place_name
	interactable.interacted.connect(travel)


## Where the courier stands on coming back through this gate.
func get_exit_point() -> Vector3:
	var exit := get_node_or_null(^"Exit") as Node3D
	return exit.global_position if exit != null else global_position + global_basis.z * 1.5


## Travels (also used by tests). False when the router refuses (a crossing is under way).
func travel(interactor: Node = null) -> bool:
	var router := get_tree().get_first_node_in_group(&"phase6_router")
	if router == null:
		return false
	return bool(router.call(&"travel", target_region, spawn, interactor, get_exit_point()))
